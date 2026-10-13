//
//  AudioHostService.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import Foundation
import os

/// AudioHostService is the object AudioHost exports: it owns the per-app pipelines and keeps them
/// in agreement with what the mixer asked for. It listens to the HAL, groups the audio processes
/// under their apps, lets the `AudioReconciler` decide, performs the actions it returns on the
/// HAL through `AppAudioPipeline`, and publishes the resulting state to the mixer.
///
/// Everything lives behind one serial control queue, plugin-engine style: a queue and value
/// state, no actors. The XPC entry points, the HAL's listeners, the wake notification and every
/// scheduled callback only hop onto the queue, and all state, HAL calls and publishes happen
/// there. A reply to `send` means the command was decoded and applied to the state ("accepted"),
/// not that it is audible: enforcement is asynchronous and comes back as a snapshot.
///
/// Time is injected twice. `clock` is the monotonic time the reconciler measures failures with,
/// and `schedule` is the only timer this type has: it asks to be called back after a delay, once.
/// The service wraps every callback so it hops onto the queue itself, whichever thread the
/// scheduler fires on. Three things use it, and none polls without a reason:
///
/// - the 3 s leave delay, one shot per app that fell silent;
/// - the 1 Hz watchdog, a chain that exists only while at least one pipeline is running;
/// - a 1 s re-check while an app is `recovering`, because that state turns into `notApplied` with
///   the passing of time alone and the mixer must be told.
///
/// AudioHost never lists or controls itself. It lives inside `Cascade.app/Contents/XPCServices/`
/// and, while a pipeline runs, its own process produces output, which grouping would fold under
/// Cascade's bundle ID: a "Cascade" column in the mixer, and a slider that would tap the very
/// output the pipelines render. So the service drops its own process from every scan
/// (`ownProcessID`) and any group under `excludedBundleIDs`, and ignores intents for them.
///
/// What the HAL listeners cost: a process or device change rescans the world (processes, outputs,
/// system output) once. A gain or mute change does not, because the slider can fire at display
/// rate and the world has not changed; it reconciles against the world last seen.
///
/// `@unchecked Sendable` is justified by confinement, not by locks: every mutable stored
/// property is read and written only on `queue`. The `let`s are immutable.
public final class AudioHostService: NSObject, AudioHostProtocol, @unchecked Sendable {

    /// How long an app stays listed after its last process stops producing output, so a gap
    /// between two songs does not make its slider vanish and come back.
    static let leaveDelay: Duration = .seconds(3)

    /// The interval of the watchdog chain.
    static let watchdogInterval: Duration = .seconds(1)

    /// The interval at which a `recovering` app is looked at again.
    static let recoveryCheckInterval: Duration = .seconds(1)

    /// How long the two pipelines of a crossfade overlap, in seconds of audio.
    static let crossfadeSeconds = 0.05

    /// How long after a crossfade begins the old pipeline is torn down: twice the fade, so the
    /// kernel has certainly finished it.
    static let crossfadeTeardownDelay: Duration = .milliseconds(100)

    /// The size at which the bundle caches are emptied when the process list changes.
    static let bundleCacheLimit = 256

    private let hal                : any AudioHostHAL
    private let queue              : DispatchQueue
    private let clock              : @Sendable () -> Duration
    private let schedule           : @Sendable (Duration, @escaping @Sendable () -> Void) -> Void
    private let publish            : @Sendable (AudioHostSnapshot) -> Void
    private let bundleInfo         : @Sendable (String) -> AudioBundleInfo?
    private let responsibleAppPath : @Sendable (Int32) -> String?
    private let notificationCenter : NotificationCenter
    private let ownProcessID       : Int32
    private let excludedBundleIDs  : Set<String>
    private let logger             = Logger(subsystem: "hylo.Cascade", category: "AudioHost")

    private var wakeObserver: (any NSObjectProtocol)?

    // MARK: Control-queue state

    private var reconciler = AudioReconciler()
    private var watchdog   = AudioHostWatchdog()
    private var intents    : [AudioAppIdentity: AudioAppIntent] = [:]
    private var world      = World()
    private var pipelines  : [UInt64: AppAudioPipeline]         = [:]
    private var presence   : [AudioAppIdentity: Presence]       = [:]

    private var bundleInfoByPath      : [String: AudioBundleInfo?] = [:]
    private var displayNameByBundleID : [String: String]           = [:]

    private var lastPublishedApps      : [AudioAppSnapshot]? = nil
    private var generation             : UInt64              = 0
    private var isWatchdogArmed        : Bool                = false
    private var isRecoveryCheckPending : Bool                = false

    /// init starts the service: the HAL listeners and the first scan happen on `queue`, and the
    /// wake observer is registered on `notificationCenter`, the workspace's by default, which
    /// tests replace with one of their own.
    ///
    /// `ownProcessID` is this process; `excludedBundleIDs` defaults to the app AudioHost is
    /// bundled in (resolved through `bundleInfo`) and AudioHost's own identifier.
    ///
    /// `responsibleExecutablePath` names the executable a process is responsible to, which is how
    /// Safari's WebKit audio process (no `.app` in its path) lands under Safari; nil uses the
    /// system's answer, and tests inject their own.
    public init(
        hal                       : any AudioHostHAL,
        queue                     : DispatchQueue,
        clock                     : @escaping @Sendable () -> Duration,
        schedule                  : @escaping @Sendable (Duration, @escaping @Sendable () -> Void) -> Void,
        publish                   : @escaping @Sendable (AudioHostSnapshot) -> Void,
        bundleInfo                : (@Sendable (String) -> AudioBundleInfo?)? = nil,
        responsibleExecutablePath : (@Sendable (Int32) -> String?)?           = nil,
        notificationCenter        : NotificationCenter?                       = nil,
        ownProcessID              : Int32                                     = getpid(),
        excludedBundleIDs         : Set<String>?                              = nil
    ) {
        let bundleInfo = bundleInfo ?? { AudioHostService.bundleInfoOnDisk(at: $0) }

        self.hal                = hal
        self.queue              = queue
        self.clock              = clock
        self.schedule           = schedule
        self.publish            = publish
        self.bundleInfo         = bundleInfo
        self.responsibleAppPath = responsibleExecutablePath ?? {
            AudioProcessResponsibility.responsibleExecutablePath(ofPID: $0)
        }
        self.notificationCenter = notificationCenter ?? NSWorkspace.shared.notificationCenter
        self.ownProcessID       = ownProcessID
        self.excludedBundleIDs  = excludedBundleIDs ?? AudioHostService.ownBundleIDs(
            bundlePath       : Bundle.main.bundlePath,
            bundleIdentifier : Bundle.main.bundleIdentifier,
            bundleInfo       : bundleInfo
        )

        super.init()

        wakeObserver = self.notificationCenter.addObserver(
            forName : NSWorkspace.didWakeNotification,
            object  : nil,
            queue   : nil
        ) { [weak self] _ in
            self?.hop { $0.environmentDidChange() }
        }

        queue.async { [self] in start() }
    }

    deinit {
        if let wakeObserver { notificationCenter.removeObserver(wakeObserver) }

        // The pipelines must be torn down on the control queue, where the HAL expects every
        // call. They are copied out because `self` is gone by the time the block runs.
        let remaining = Array(pipelines.values)

        queue.async { remaining.forEach { $0.teardown() } }
    }

    /// start registers the HAL listeners and takes the first picture of the world.
    private func start() {
        hal.listen(
            onProcesses      : { [weak self] in self?.hop { $0.worldDidChange() } },
            onDevices        : { [weak self] in self?.hop { $0.worldDidChange() } },
            onServiceRestart : { [weak self] in self?.hop { $0.environmentDidChange() } }
        )

        worldDidChange()
    }

    /// hop runs `work` on the control queue. Listeners and notifications call it from wherever
    /// they were delivered; the service is passed in so the closure holds no weak variable.
    private func hop(_ work: @escaping @Sendable (AudioHostService) -> Void) {
        queue.async { [self] in work(self) }
    }

    // MARK: - AudioHostProtocol

    public func hello(reply: @escaping @Sendable (Int32) -> Void) {
        reply(getpid())
    }

    public func send(
        _ command: Data,
        reply    : @escaping @Sendable (Bool) -> Void
    ) {
        queue.async { [self] in
            guard let decoded = try? AudioHostWire.decode(AudioHostCommand.self, from: command) else {
                logger.error("Audio command rejected: it did not decode")
                reply(false)
                return
            }

            apply(decoded)
            reply(true)
        }
    }

    /// republish sends the current state to the mixer whether or not it changed. The listener
    /// calls it when a connection starts, because a snapshot is otherwise published only on a
    /// change and a mixer that connects to a quiet AudioHost would never get one.
    public func republish() {
        queue.async { [self] in
            lastPublishedApps = nil

            publishIfChanged()
        }
    }

    // MARK: - Commands

    private func apply(_ command: AudioHostCommand) {
        switch command {
            case .replaceIntents(let replacement):
                intents = replacement.filter { !$0.value.isNeutral && !isExcluded($0.key) }

            case .setIntent(let identity, let intent):
                intents[identity] = intent.isNeutral || isExcluded(identity) ? nil : intent

            case .returnToNative(let identity):
                // The neutral intent is what clears a native fallback: the reducer tears the
                // pipeline down and forgets the failure history when nothing is asked of an app.
                intents[identity] = nil
        }

        settle()
    }

    // MARK: - Events

    /// worldDidChange is the HAL's "something about processes or devices moved": rescan once,
    /// then reconcile against the fresh picture.
    private func worldDidChange() {
        trimBundleCaches()
        world = scanWorld()

        settle()
    }

    /// environmentDidChange is a wake or a coreaudiod restart: every HAL object behind a pipeline
    /// may be stale while every ID and UID still compares equal, so the reconciler rebuilds them.
    private func environmentDidChange() {
        world = scanWorld()

        execute(reconciler.environmentInvalidated(now: clock()))
        settle()
    }

    /// settle reconciles the intents against the world last seen and brings the bookkeeping
    /// (who is listed, the watchdog, the published snapshot) up to date.
    private func settle() {
        let actions = reconciler.reconcile(
            intents         : intents,
            apps            : world.apps,
            outputs         : world.outputs,
            systemOutputUID : world.systemOutputUID,
            now             : clock()
        )

        execute(actions)
        afterChange()
    }

    private func afterChange() {
        updatePresence()
        armWatchdogIfNeeded()
        publishIfChanged()
    }

    // MARK: - World

    /// World is the picture of the system the reconciler works from: the processes grouped under
    /// their apps, the devices that can play, and the system output.
    private struct World {

        var apps            : [AudioAppIdentity: [AudioProcessRecord]] = [:]
        var outputs         : Set<String>                              = []
        var systemOutputUID : String?                                  = nil
    }

    private func scanWorld() -> World {
        // Our own process goes before grouping, so it can neither show up nor join the group of
        // the app it is bundled in; the excluded bundles are dropped after, once they are named.
        let grouped = AudioProcessGrouping.group(
            hal.processes().filter { $0.pid != ownProcessID },
            bundleIDOfApp      : { [self] appPath in
                resolvedBundleInfo(at: appPath)?.bundleID
            },
            responsibleAppPath : responsibleAppPath
        )
        .filter { !isExcluded($0.key) }

        return World(
            apps            : grouped,
            outputs         : hal.outputUIDs(),
            systemOutputUID : hal.systemOutputUID()
        )
    }

    private func isExcluded(_ identity: AudioAppIdentity) -> Bool {
        excludedBundleIDs.contains(identity.bundleID)
    }

    /// ownBundleIDs names what AudioHost must never list: the bundle ID of the outermost `.app`
    /// that contains `bundlePath` (`Cascade.app` for `Cascade.app/Contents/XPCServices/AudioHost.xpc`,
    /// the identity grouping gives AudioHost's own process) and the `bundleIdentifier` of AudioHost
    /// itself. Empty when neither resolves, as in a bare command-line tool.
    static func ownBundleIDs(
        bundlePath       : String,
        bundleIdentifier : String?,
        bundleInfo       : (String) -> AudioBundleInfo?
    ) -> Set<String> {
        var bundleIDs = Set<String>()

        if
            let appPath = AudioProcessGrouping.outermostApp(of: bundlePath),
            let info    = bundleInfo(appPath)
        {
            bundleIDs.insert(info.bundleID)
        }

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            bundleIDs.insert(bundleIdentifier)
        }

        return bundleIDs
    }

    /// resolvedBundleInfo reads an app bundle once per path: the disk read is the expensive part
    /// of grouping, and the same few paths come back at every scan.
    private func resolvedBundleInfo(at appPath: String) -> AudioBundleInfo? {
        if let cached = bundleInfoByPath[appPath] { return cached }

        let info = bundleInfo(appPath)

        bundleInfoByPath.updateValue(info, forKey: appPath)

        if let info { displayNameByBundleID[info.bundleID] = info.displayName }

        return info
    }

    /// trimBundleCaches empties the caches only when they grew past the limit, which takes a
    /// long session of short-lived apps; a stable set of apps never pays for a re-read.
    private func trimBundleCaches() {
        guard bundleInfoByPath.count > Self.bundleCacheLimit else { return }

        bundleInfoByPath      = [:]
        displayNameByBundleID = [:]
    }

    /// bundleInfoOnDisk reads the identifier and name of the bundle at `path`. The name is the
    /// localised display name when the bundle has one, else its plain name, else its identifier.
    static func bundleInfoOnDisk(at path: String) -> AudioBundleInfo? {
        guard
            let bundle   = Bundle(path: path),
            let bundleID = bundle.bundleIdentifier,
            !bundleID.isEmpty
        else { return nil }

        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        let name        = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String

        return AudioBundleInfo(
            bundleID    : bundleID,
            displayName : [displayName, name].compactMap { $0 }.first { !$0.isEmpty } ?? bundleID
        )
    }

    // MARK: - Executing actions

    /// execute performs the reconciler's actions in order. Performing one may produce more (a
    /// build reports its outcome and the reducer answers), which are appended and performed
    /// after the ones already queued.
    private func execute(_ initial: [AudioReconcileAction]) {
        var actions = initial
        var index   = 0

        while index < actions.count {
            let action = actions[index]

            index += 1
            actions.append(contentsOf: perform(action))
        }
    }

    private func perform(_ action: AudioReconcileAction) -> [AudioReconcileAction] {
        switch action {
            case .build(let identity, let token, let configuration, let intent):
                let pipeline = AppAudioPipeline(
                    identity      : identity,
                    token         : token,
                    configuration : configuration,
                    intent        : intent,
                    hal           : hal
                )

                pipelines[token] = pipeline

                return reconciler.built(identity, token: token, succeeded: pipeline != nil, now: clock())

            case .crossfade(let identity, let from, let to, let configuration, let intent):
                return performCrossfade(
                    of            : identity,
                    from          : from,
                    to            : to,
                    configuration : configuration,
                    intent        : intent
                )

            case .updateCommand(_, let token, let intent):
                pipelines[token]?.update(intent)

                return []

            case .teardown(_, let token):
                pipelines.removeValue(forKey: token)?.teardown()

                return []

            case .scheduleRetry(_, let delay):
                scheduleOnQueue(delay) { $0.retryDidFire() }

                return []
        }
    }

    /// performCrossfade builds the new pipeline beside the old one and hands the audio over.
    ///
    /// The old pipeline is touched only once the new one is up, so a failed build leaves it
    /// running at full weight, exactly as it was. On success both fades start in the same step,
    /// 50 ms of equal-power handover, and the old pipeline is torn down 100 ms later through the
    /// scheduler, so the two overlap for at most that long.
    private func performCrossfade(
        of identity   : AudioAppIdentity,
        from          : UInt64,
        to            : UInt64,
        configuration : AudioPipelineConfiguration,
        intent        : AudioAppIntent
    ) -> [AudioReconcileAction] {
        let incoming = AppAudioPipeline(
            identity      : identity,
            token         : to,
            configuration : configuration,
            intent        : intent,
            hal           : hal
        )

        guard let incoming else {
            return reconciler.built(identity, token: to, succeeded: false, now: clock())
        }

        let frames = UInt32((incoming.sampleRate * Self.crossfadeSeconds).rounded())

        incoming.beginCrossfade(fadingIn: true, frames: frames)
        pipelines[from]?.beginCrossfade(fadingIn: false, frames: frames)
        pipelines[to] = incoming

        scheduleOnQueue(Self.crossfadeTeardownDelay) { service in
            service.pipelines.removeValue(forKey: from)?.teardown()
        }

        return reconciler.built(identity, token: to, succeeded: true, now: clock())
    }

    /// retryDidFire rescans before it reconciles: a retry is rare, and a device that was the
    /// reason for the failure may be back without anyone having told us.
    private func retryDidFire() {
        world = scanWorld()

        settle()
    }

    /// scheduleOnQueue asks the injected scheduler for one callback and makes it run on the
    /// control queue, whatever thread the scheduler fires on. It holds the service weakly, so a
    /// pending timer never keeps a stopped service alive.
    private func scheduleOnQueue(
        _ delay : Duration,
        _ work  : @escaping @Sendable (AudioHostService) -> Void
    ) {
        schedule(delay) { [weak self] in
            guard let self else { return }

            self.queue.async { work(self) }
        }
    }

    // MARK: - Presence

    /// Presence is how long an app has been silent, nil while it produces output.
    private struct Presence {

        var silentSince: Duration?
    }

    /// updatePresence lists every app with a process producing output, and starts the leave
    /// delay of the ones that just fell silent.
    private func updatePresence() {
        let now = clock()

        for (identity, records) in world.apps where records.contains(where: \.isRunningOutput) {
            presence[identity] = Presence(silentSince: nil)
        }

        for identity in presence.keys.sorted(by: { $0.bundleID < $1.bundleID }) {
            guard
                presence[identity]?.silentSince == nil,
                !isProducingOutput(identity)
            else { continue }

            presence[identity]?.silentSince = now

            scheduleOnQueue(Self.leaveDelay) { $0.leaveDidFire() }
        }
    }

    private func isProducingOutput(_ identity: AudioAppIdentity) -> Bool {
        world.apps[identity]?.contains(where: \.isRunningOutput) ?? false
    }

    /// leaveDidFire removes every app that has been silent for the whole delay. An app that
    /// resumed in the meantime has no `silentSince`, and one that fell silent again has a newer
    /// one and its own pending check, so a stale callback removes nothing it should not.
    private func leaveDidFire() {
        let now = clock()

        for (identity, entry) in presence {
            guard let silentSince = entry.silentSince, now - silentSince >= Self.leaveDelay else { continue }

            presence[identity] = nil
        }

        afterChange()
    }

    // MARK: - Watchdog

    /// armWatchdogIfNeeded starts the 1 Hz chain when a pipeline is running and none is pending.
    /// The chain re-arms itself only while a pipeline runs, so an AudioHost with nothing tapped
    /// has no timer at all.
    private func armWatchdogIfNeeded() {
        guard !isWatchdogArmed, !runningPipelines().isEmpty else { return }

        isWatchdogArmed = true

        scheduleOnQueue(Self.watchdogInterval) { $0.watchdogDidFire() }
    }

    private func runningPipelines() -> [AppAudioPipeline] {
        pipelines.values
            .filter { pipeline in
                if case .running(let token, _) = reconciler.state(of: pipeline.identity) {
                    return token == pipeline.token
                }

                return false
            }
            .sorted { $0.identity.bundleID < $1.identity.bundleID }
    }

    /// watchdogDidFire samples every running pipeline. A stalled one is reported to the reconciler
    /// as a broken running pipeline, which tears it down and starts the retry ladder.
    private func watchdogDidFire() {
        isWatchdogArmed = false

        let samples = runningPipelines().map { pipeline in
            AudioHostWatchdog.Sample(
                identity       : pipeline.identity,
                token          : pipeline.token,
                callbackCount  : pipeline.callbackCount,
                isOutputActive : isProducingOutput(pipeline.identity)
            )
        }

        var actions: [AudioReconcileAction] = []

        for stall in watchdog.tick(samples) {
            logger.error("Audio pipeline stalled: \(stall.identity.bundleID, privacy: .public)")

            actions += reconciler.built(stall.identity, token: stall.token, succeeded: false, now: clock())
        }

        execute(actions)
        afterChange()
    }

    // MARK: - Snapshot

    /// publishIfChanged builds the snapshot and sends it only when its apps differ from the last
    /// one sent; the generation counts the snapshots that were sent.
    private func publishIfChanged() {
        let apps = makeApps()

        scheduleRecoveryCheckIfNeeded(for: apps)

        guard apps != lastPublishedApps else { return }

        guard let snapshot = try? AudioHostSnapshot(generation: generation + 1, apps: apps, captureAllowed: nil) else {
            logger.error("Audio snapshot not published: it failed its own validation")
            return
        }

        generation        += 1
        lastPublishedApps  = apps

        publish(snapshot)
    }

    /// makeApps describes every listed app, sorted by the name the user sees. An app whose
    /// snapshot would not validate is left out rather than breaking the whole report.
    private func makeApps() -> [AudioAppSnapshot] {
        let now = clock()

        let apps = presence.keys.compactMap { identity in
            try? AudioAppSnapshot(
                identity            : identity,
                displayName         : displayName(of: identity),
                intent              : intents[identity] ?? .neutral,
                enforcement         : reconciler.enforcement(of: identity, now: now),
                effectiveOutputUIDs : effectiveOutputUIDs(of: identity)
            )
        }

        return apps
            .sorted { left, right in
                let order = left.displayName.caseInsensitiveCompare(right.displayName)

                return order == .orderedSame
                    ? left.identity.bundleID < right.identity.bundleID
                    : order == .orderedAscending
            }
            .prefix(AudioHostSnapshot.maximumApps)
            .map { $0 }
    }

    /// displayName is the bundle's name, or the bundle ID when none is known or the name would
    /// not fit the contract's limit.
    private func displayName(of identity: AudioAppIdentity) -> String {
        let name = displayNameByBundleID[identity.bundleID] ?? identity.bundleID

        return name.utf8.count <= AudioAppSnapshot.maximumDisplayNameBytes ? name : identity.bundleID
    }

    /// effectiveOutputUIDs is where the sound goes: the outputs of the pipeline when one exists
    /// or is being built, the system output when the app plays natively.
    private func effectiveOutputUIDs(of identity: AudioAppIdentity) -> [String] {
        switch reconciler.state(of: identity) {
            case .building(_, let configuration),
                 .running(_, let configuration),
                 .crossfading(_, _, let configuration):
                return configuration.outputUIDs

            case .none, .failed, .native:
                return world.systemOutputUID.map { [$0] } ?? []
        }
    }

    /// scheduleRecoveryCheckIfNeeded covers the one enforcement that changes with time alone:
    /// `recovering` becomes `notApplied` three seconds after a failure began, with no event to
    /// say so. While an app is recovering, look again every second; the window is three seconds
    /// long and ends by itself, so this is not a poll.
    private func scheduleRecoveryCheckIfNeeded(for apps: [AudioAppSnapshot]) {
        guard
            !isRecoveryCheckPending,
            apps.contains(where: { $0.enforcement == .recovering })
        else { return }

        isRecoveryCheckPending = true

        scheduleOnQueue(Self.recoveryCheckInterval) { service in
            service.isRecoveryCheckPending = false
            service.publishIfChanged()
        }
    }
}
