//
//  PluginKernel.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// PluginKernel is the engine's decision core: registry, broker, supervisor and scheduler as one
/// value-type state machine. Every operation takes the current instant and returns the effects
/// to perform, so the whole failure table runs in tests with no thread, timer or plugin, and the
/// engine around it only locks, calls out and rearms one timer from `nextDelay`.
///
/// One event is in flight per plugin. Events that arrive meanwhile wait in the plugin's mailbox,
/// where sources coalesce to their latest state. A dispatch arms the watchdog at
/// `handleDeadline`. A plugin over its CPU or publication budget is held, not refused, until the
/// budget allows its next event, but an action waits at most `actionTimeout`, after which the
/// renderer has reverted it and it is refused instead of run late. While nothing is pending, due
/// or in flight, `nextDelay` is nil and the engine sleeps.
struct PluginKernel: Sendable {

    static let handleDeadline = Duration.milliseconds(250)
    static let actionTimeout  = Duration.milliseconds(1_500)
    static let minimumWake    = 1.0
    static let maximumSleep   = 86_400.0

    private let capabilities: PluginHostCapabilities
    private let policy      : any PluginHealthPolicy
    private var records     : [PluginID: PluginRecord] = [:]
    private var leases      = PluginSourceLeases()
    private var store       = PluginPublicationStore()
    private var visible     : Set<PluginPublicationKey> = []
    private var lastToken   : UInt64 = 0
    private var isHostReady = true

    init(
        capabilities: PluginHostCapabilities,
        policy      : any PluginHealthPolicy
    ) {
        self.capabilities = capabilities
        self.policy       = policy
    }

    func state(of plugin: PluginID) -> PluginState? {
        records[plugin].map { record in
            switch record.status {
                case .idle, .handling, .retrying: .active
                case .disabledAfterHang         : .disabledAfterHang
                case .quarantined               : .quarantined
            }
        }
    }

    /// register admits a plugin with the grants its approver gave it, keeping only permissions
    /// its manifest declares, and asks it for its content. A second registration of the same id
    /// is ignored.
    mutating func register(
        _ manifest: PluginManifest,
        grants    : Set<String>,
        at now    : PluginInstant
    ) -> [PluginEngineEffect] {
        guard records[manifest.id] == nil else { return [] }

        var effects: [PluginEngineEffect] = [.start(manifest.id, entryPoint: manifest.execution.entryPoint)]
        var record  = PluginRecord(
            manifest: manifest,
            grants  : grants.intersection(manifest.features.flatMap(\.permissions)),
            at      : now.monotonic
        )
        resume(manifest.id, &record, &effects)
        records[manifest.id] = record

        schedule(at: now, into: &effects)
        return effects
    }

    /// receive hands a source's latest state to every plugin holding the source.
    mutating func receive(
        _ event: PluginSourceEvent,
        at now : PluginInstant
    ) -> [PluginEngineEffect] {
        for plugin in leases.record(event) {
            records[plugin]?.mailbox.post(.source(event))
        }

        var effects: [PluginEngineEffect] = []
        schedule(at: now, into: &effects)
        return effects
    }

    /// setVisible records which surfaces are on screen. A surface that becomes visible with stale
    /// content asks its plugin for one refresh, and asking renews the content's age, so a plugin
    /// with nothing new is not asked again on the next opening; opening and closing the notch
    /// otherwise wakes no plugin.
    mutating func setVisible(
        _ isVisible: Bool,
        for key    : PluginPublicationKey,
        at now     : PluginInstant
    ) -> [PluginEngineEffect] {
        guard isVisible else {
            visible.remove(key)
            return []
        }
        guard visible.insert(key).inserted,
              store.isStale(key, at: now.wall),
              records[key.plugin]?.isRunnable == true
        else { return [] }

        store.renew(key, at: now.wall)
        records[key.plugin]?.mailbox.post(.refresh)

        var effects: [PluginEngineEffect] = []
        schedule(at: now, into: &effects)
        return effects
    }

    /// submit checks a renderer's request with the broker and queues the resulting event ahead
    /// of everything else pending. A refused request comes back as `reject`, so the renderer
    /// reverts its optimistic value at once.
    mutating func submit(
        _ request: PluginActionRequest,
        at now   : PluginInstant
    ) -> [PluginEngineEffect] {
        guard var record = records[request.key.plugin],
              record.isRunnable,
              let feature = availableFeature(request.key.feature, of: record),
              let event = PluginActionAuthorizer.event(for: request, entry: store[request.key], feature: feature),
              record.mailbox.queue(PluginMailbox.Action(event: event, request: request, postedAt: now.monotonic))
        else { return [.reject(request)] }

        records[request.key.plugin] = record

        var effects: [PluginEngineEffect] = []
        schedule(at: now, into: &effects)
        return effects
    }

    /// complete takes a plugin's answer to the dispatch `token` named. An answer to anything but
    /// the dispatch in flight, such as a hung plugin returning after the watchdog gave up on it,
    /// is ignored. The output is applied first, then the CPU it cost is charged. An answer that
    /// arrives after the user switched the plugin off is dropped.
    mutating func complete(
        _ plugin: PluginID,
        token   : UInt64,
        result  : PluginExecutionResult,
        at now  : PluginInstant
    ) -> [PluginEngineEffect] {
        guard var record = records[plugin], case .handling(token, _) = record.status else { return [] }

        var effects: [PluginEngineEffect] = []
        record.status = .idle

        switch result.outcome {
            case .output(let output):
                if record.isEnabled {
                    accept(output, from: plugin, &record, at: now, &effects)
                }

            case .failed:
                react(to: .threw, plugin, &record, at: now, &effects)

            case .lost:
                if record.isEnabled {
                    prime(&record)
                }
        }

        let rest = record.cpu.charge(result.cpuTime, at: now.monotonic)
        if rest > .zero, record.isRunnable {
            record.throttledUntil = max(record.throttledUntil, now.monotonic + rest)
            react(to: .overBudget, plugin, &record, at: now, &effects)
        }

        records[plugin] = record
        schedule(at: now, into: &effects)
        return effects
    }

    /// tick runs whatever came due: the watchdog of a dispatch past its deadline, a retry whose
    /// pause is over, a wake a plugin asked for, and any held event its budgets now allow.
    mutating func tick(at now: PluginInstant) -> [PluginEngineEffect] {
        var effects: [PluginEngineEffect] = []

        for plugin in records.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard var record = records[plugin] else { continue }

            switch record.status {
                case .handling(_, let deadline) where now.monotonic >= deadline:
                    effects.append(.stop(plugin))
                    record.status = .idle
                    react(to: .hung, plugin, &record, at: now, &effects)
                    if record.isRunnable {
                        effects.append(.start(plugin, entryPoint: record.manifest.execution.entryPoint))
                    }
                    if record.status == .idle {
                        prime(&record)
                    }

                case .retrying(let until) where now.monotonic >= until:
                    record.status = .idle
                    if record.isEnabled {
                        prime(&record)
                    }

                default:
                    break
            }

            if let wake = record.wake, wake <= now.wall, record.isRunnable {
                record.wake = nil
                record.mailbox.post(.wake)
            }

            records[plugin] = record
        }

        schedule(at: now, into: &effects)
        return effects
    }

    /// revoke takes a permission back with immediate effect: the features that declare it
    /// withdraw their content and release their sources, and their actions are refused.
    mutating func revoke(
        _ permission: String,
        from plugin : PluginID,
        at now      : PluginInstant
    ) -> [PluginEngineEffect] {
        guard var record = records[plugin], record.grants.remove(permission) != nil else { return [] }

        var effects: [PluginEngineEffect] = []
        let lost = Set(record.manifest.features.filter { $0.permissions.contains(permission) }.map(\.id))
        withdraw(plugin, features: lost, &effects)
        syncLeases(plugin, &record, &effects)
        records[plugin] = record
        return effects
    }

    /// grant gives back a declared permission and asks the plugin for what it can now show.
    mutating func grant(
        _ permission: String,
        to plugin   : PluginID,
        at now      : PluginInstant
    ) -> [PluginEngineEffect] {
        guard var record = records[plugin],
              record.manifest.features.contains(where: { $0.permissions.contains(permission) }),
              record.grants.insert(permission).inserted
        else { return [] }

        var effects: [PluginEngineEffect] = []
        if record.isRunnable {
            resume(plugin, &record, &effects)
        }
        records[plugin] = record

        schedule(at: now, into: &effects)
        return effects
    }

    /// reenable is the user's way back for a stopped plugin. A quarantined one also gets a clean
    /// history; one disabled after a hang keeps it, so a second hang quarantines it.
    mutating func reenable(
        _ plugin: PluginID,
        at now  : PluginInstant
    ) -> [PluginEngineEffect] {
        guard var record = records[plugin], record.isEnabled, !record.isRunnable else { return [] }

        if record.status == .quarantined {
            record.history = PluginHealthHistory()
        }
        record.status = .idle

        var effects: [PluginEngineEffect] = [.start(plugin, entryPoint: record.manifest.execution.entryPoint)]
        resume(plugin, &record, &effects)
        records[plugin] = record

        schedule(at: now, into: &effects)
        return effects
    }

    /// setEnabled is the user's switch for a plugin, apart from its health. A plugin switched off
    /// stays loaded in its host but runs nothing: its content leaves the screen, its sources are
    /// released and an answer still in flight is dropped. Switched on, it leases its sources again
    /// and is asked for its content.
    mutating func setEnabled(
        _ isEnabled: Bool,
        for plugin : PluginID,
        at now     : PluginInstant
    ) -> [PluginEngineEffect] {
        guard var record = records[plugin], record.isEnabled != isEnabled else { return [] }

        let wasRunnable  = record.isRunnable
        record.isEnabled = isEnabled

        var effects: [PluginEngineEffect] = []
        if wasRunnable, !record.isRunnable {
            halt(plugin, &record, &effects)
        } else if !wasRunnable, record.isRunnable {
            resume(plugin, &record, &effects)
        }
        records[plugin] = record

        schedule(at: now, into: &effects)
        return effects
    }

    /// invoke runs an action the host asks for on the user's behalf, such as a preview chosen in
    /// Cascade's menu. It reaches the plugin only while the plugin runs and the feature is
    /// available and declares the action; with no control to revert, a refused one is dropped.
    mutating func invoke(
        _ action : String,
        value    : PluginValue?,
        feature  : String,
        of plugin: PluginID,
        at now   : PluginInstant
    ) -> [PluginEngineEffect] {
        guard var record = records[plugin],
              record.isRunnable,
              let declared = availableFeature(feature, of: record),
              declared.actions.contains(action),
              let event = try? PluginActionEvent(feature: feature, action: action, value: value),
              record.mailbox.queue(PluginMailbox.Action(event: event, request: nil, postedAt: now.monotonic))
        else { return [] }

        records[plugin] = record

        var effects: [PluginEngineEffect] = []
        schedule(at: now, into: &effects)
        return effects
    }

    /// hostAvailable resumes dispatching once the executor's host has completed a handshake. A
    /// host that restarted lost every plugin's state, so every runnable plugin leases its sources
    /// again, each of which starts by emitting its current state, and is asked for its content.
    mutating func hostAvailable(at now: PluginInstant) -> [PluginEngineEffect] {
        isHostReady = true

        var effects: [PluginEngineEffect] = []
        for plugin in records.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard var record = records[plugin], record.isRunnable else { continue }

            syncLeases(plugin, &record, &effects)
            prime(&record)
            records[plugin] = record
        }

        schedule(at: now, into: &effects)
        return effects
    }

    /// hostUnavailable holds every dispatch while the host is gone and releases every source.
    /// Nothing comes due until the host is back, so a dead host costs nothing, and a source the
    /// kernel runs for a plugin that cannot run stops instead of working for no one: the volume
    /// source's key tap lets macOS show its own HUD again rather than swallow keys silently.
    mutating func hostUnavailable() -> [PluginEngineEffect] {
        isHostReady = false

        var effects: [PluginEngineEffect] = []
        for plugin in records.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard var record = records[plugin] else { continue }

            syncLeases(plugin, &record, &effects)
            records[plugin] = record
        }

        return effects
    }

    /// nextDelay is how long the engine's one timer may sleep: until the earliest watchdog,
    /// retry, held event or wake, and at most a day. Nil means nothing is due.
    func nextDelay(at now: PluginInstant) -> Duration? {
        [deadlineDelay(at: now), wakeDelay(at: now)].compactMap { $0 }.min()
    }

    /// wakeDelay is how long until the earliest wake a plugin asked for, at most a day. Wakes are
    /// civil times, so the engine waits for one on the wall clock, which keeps running while the
    /// Mac sleeps; everything else waits on uptime, which a clock change cannot move.
    func wakeDelay(at now: PluginInstant) -> Duration? {
        records.values
            .filter(\.isRunnable)
            .compactMap(\.wake)
            .min()
            .map { wake in .seconds(min(max(0, wake.timeIntervalSince(now.wall)), Self.maximumSleep)) }
    }

    /// deadlineDelay is how long until the earliest watchdog, retry or held event.
    private func deadlineDelay(at now: PluginInstant) -> Duration? {
        records.values
            .compactMap { record -> Duration? in
                switch record.status {
                    case .handling(_, let deadline)                        : deadline
                    case .retrying(let until)                              : until
                    case .idle where isHostReady && !record.mailbox.isEmpty: record.throttledUntil
                    default                                                : nil
                }
            }
            .min()
            .map { max(.zero, $0 - now.monotonic) }
    }

    /// schedule dispatches the next pending event of every idle plugin its budgets allow.
    private mutating func schedule(
        at now      : PluginInstant,
        into effects: inout [PluginEngineEffect]
    ) {
        guard isHostReady else { return }

        for plugin in records.keys.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard var record = records[plugin],
                  record.status == .idle,
                  now.monotonic >= record.throttledUntil
            else { continue }

            if let event = next(from: &record, at: now, &effects) {
                lastToken    += 1
                record.status = .handling(token: lastToken, deadline: now.monotonic + Self.handleDeadline)
                effects.append(.dispatch(plugin, event, token: lastToken))
            }
            records[plugin] = record
        }
    }

    /// next takes the plugin's next deliverable event. Grants are checked again here, so a source
    /// state or an action that waited while a permission was revoked is not delivered; an action
    /// that waited past `actionTimeout`, which the renderer has already reverted, is refused
    /// rather than run late.
    private func next(
        from record: inout PluginRecord,
        at now     : PluginInstant,
        _ effects  : inout [PluginEngineEffect]
    ) -> PluginEvent? {
        while let item = record.mailbox.take() {
            switch item {
                case .event(.source(let state)) where !record.leased.contains(state.source):
                    continue

                case .event(let event):
                    return event

                case .action(let action):
                    guard now.monotonic - action.postedAt <= Self.actionTimeout,
                          availableFeature(action.event.feature, of: record) != nil
                    else {
                        if let request = action.request {
                            effects.append(.reject(request))
                        }
                        continue
                    }

                    return .action(action.event)
            }
        }

        return nil
    }

    /// accept stores each publication of an output on its own, so one bad publication leaves
    /// the others standing, spends one publication token when anything changed on screen, and
    /// takes the wake the output asked for, never sooner than a second away.
    private mutating func accept(
        _ output   : PluginOutput,
        from plugin: PluginID,
        _ record   : inout PluginRecord,
        at now     : PluginInstant,
        _ effects  : inout [PluginEngineEffect]
    ) {
        var changes   : [PluginPublicationChange] = []
        var isRejected = false
        for publication in output.publications {
            do {
                if let change = try publish(publication, by: plugin, record, at: now) {
                    changes.append(change)
                }
            } catch {
                isRejected = true
            }
        }

        if !changes.isEmpty {
            let rest = changes.allSatisfy { $0.key.surface == .notice }
                ? record.noticeBudget.spend(at: now.monotonic)
                : record.budget.spend(at: now.monotonic)

            effects.append(.deliver(changes))
            record.throttledUntil = max(record.throttledUntil, now.monotonic + rest)
        }
        record.wake = output.wake.map { max($0, now.wall.addingTimeInterval(Self.minimumWake)) }

        if isRejected {
            react(to: .invalidPublication, plugin, &record, at: now, &effects)
        }
    }

    /// publish checks what the plugin could have known: the feature and surface exist in its
    /// manifest, and the document shows only components the feature declared. A feature the
    /// host made unavailable is not the plugin's fault, so its publication is dropped quietly.
    private mutating func publish(
        _ publication: PluginPublication,
        by plugin    : PluginID,
        _ record     : PluginRecord,
        at now       : PluginInstant
    ) throws -> PluginPublicationChange? {
        guard let feature = record.manifest.features.first(where: { $0.id == publication.feature }),
              feature.surfaces.declares(publication.surface),
              publication.document.map({ $0.componentReferences.isSubset(of: feature.components) }) ?? true
        else {
            throw AddonFailure(code: .invalidPayload, reason: "Publication outside its feature's declarations")
        }
        guard isAvailable(feature, in: record) else { return nil }

        let key = PluginPublicationKey(plugin: plugin, feature: feature.id, surface: publication.surface)
        guard let document = publication.document else { return store.withdraw(key) }

        return store.apply(
            document,
            staleAfter: publication.staleAfter,
            for       : key,
            at        : now.wall,
            notice    : publication.notice
        )
    }

    /// react applies the health policy's answer to an incident.
    private mutating func react(
        to incident: PluginIncident,
        _ plugin   : PluginID,
        _ record   : inout PluginRecord,
        at now     : PluginInstant,
        _ effects  : inout [PluginEngineEffect]
    ) {
        switch policy.reaction(to: incident, history: &record.history, at: now.monotonic) {
            case .keep:
                break

            case .retry(let delay):
                record.status = .retrying(until: now.monotonic + delay)
                record.mailbox.removeAll()

            case .disable:
                record.status = .disabledAfterHang
                halt(plugin, &record, &effects)

            case .quarantine:
                record.status = .quarantined
                halt(plugin, &record, &effects)
        }
    }

    /// halt stops a plugin that will not run again until the user acts: its pending events and
    /// wake go, its content leaves the screen and its sources are released.
    private mutating func halt(
        _ plugin : PluginID,
        _ record : inout PluginRecord,
        _ effects: inout [PluginEngineEffect]
    ) {
        record.mailbox.removeAll()
        record.wake = nil
        withdraw(plugin, features: nil, &effects)
        syncLeases(plugin, &record, &effects)
    }

    /// resume leases the sources a runnable plugin needs and primes it.
    private mutating func resume(
        _ plugin : PluginID,
        _ record : inout PluginRecord,
        _ effects: inout [PluginEngineEffect]
    ) {
        syncLeases(plugin, &record, &effects)
        prime(&record)
    }

    /// prime queues the latest state of every source the plugin holds and a refresh, which is
    /// all a plugin that lost its memory needs to rebuild its content.
    private func prime(_ record: inout PluginRecord) {
        for event in leases.latest(of: record.leased) {
            record.mailbox.post(.source(event))
        }
        record.mailbox.post(.refresh)
    }

    /// syncLeases makes the plugin hold exactly the sources its available features declare
    /// while it is runnable and its host is there, and none otherwise, starting and stopping
    /// shared sources as their first holder arrives and their last one leaves.
    private mutating func syncLeases(
        _ plugin : PluginID,
        _ record : inout PluginRecord,
        _ effects: inout [PluginEngineEffect]
    ) {
        let current = record
        let wanted  = current.isRunnable && isHostReady
            ? Set(current.manifest.features.filter { isAvailable($0, in: current) }.flatMap(\.sources))
            : []

        for source in wanted.subtracting(current.leased).sorted() {
            if leases.lease(source, for: plugin) {
                effects.append(.startSource(source))
            }
        }
        for source in current.leased.subtracting(wanted).sorted() {
            if leases.release(source, for: plugin) {
                effects.append(.stopSource(source))
            }
        }
        record.leased = wanted
    }

    /// withdraw takes a plugin's content off screen, for the given features or all of them.
    private mutating func withdraw(
        _ plugin : PluginID,
        features : Set<String>?,
        _ effects: inout [PluginEngineEffect]
    ) {
        var changes: [PluginPublicationChange] = []
        for key in store.keys(of: plugin) where features?.contains(key.feature) ?? true {
            if let change = store.withdraw(key) {
                changes.append(change)
            }
        }

        if !changes.isEmpty {
            effects.append(.deliver(changes))
        }
    }

    private func isAvailable(
        _ feature: PluginFeature,
        in record: PluginRecord
    ) -> Bool {
        capabilities.sources.isSuperset(of: feature.sources)
            && capabilities.services.isSuperset(of: feature.services)
            && capabilities.components.isSuperset(of: feature.components.map(\.id))
            && record.grants.isSuperset(of: feature.permissions)
    }

    private func availableFeature(
        _ id     : String,
        of record: PluginRecord
    ) -> PluginFeature? {
        record.manifest.features.first { $0.id == id && isAvailable($0, in: record) }
    }
}
