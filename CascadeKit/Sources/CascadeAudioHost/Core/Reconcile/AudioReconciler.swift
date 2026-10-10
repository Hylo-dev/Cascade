//
//  AudioReconciler.swift
//  CascadeKit
//

import CascadeContracts

/// AudioReconciler is the decision core of AudioHost's per-app control: a value-type reducer that
/// turns what the user asked for (intents) and what the system looks like (running processes,
/// output devices) into the pipeline actions that make the two agree. It performs no I/O and
/// touches no HAL, so every lifecycle rule below is a plain unit test.
///
/// The reducer owns one entry per app: the pipeline state, the intent last seen, the intent last
/// sent to the pipeline and the failure history. The caller keeps a single instance behind its
/// own lock, feeds it the world through `reconcile`, reports build outcomes through `built`, and
/// performs the returned actions. Tokens only grow, so an answer for a build that was replaced
/// in the meantime is recognised and dropped.
///
/// The rules, in the order they bite:
///
/// - A pipeline exists only for a non-neutral intent, an app with at least one process currently
///   producing output, and at least one output to render to. Anything else tears it down.
/// - The effective outputs are the intent's outputs that exist, in the intent's order; when none
///   exists, or the intent follows the system, the system output. The stored intent is never
///   rewritten, so a preferred device that comes back is honoured again by the next call.
/// - A change on a running pipeline is a `crossfade` when the outputs changed and the old
///   outputs still exist, so audio never drops. A change in the tapped processes alone (a helper
///   joined or left) is a teardown and a fresh build: the tap itself must be rebuilt, and there
///   is nothing to crossfade between.
/// - A failed build is retried after 0, 100, 300 and 1000 ms, then left alone. The failure
///   episode started at the first failure; within three seconds of it the app is `recovering`,
///   after that `notApplied`. A second episode for the identical configuration means the
///   configuration is hopeless: the app goes `native` and nothing is built until its
///   configuration changes, the intent turns neutral, or the environment is invalidated. A gain
///   or mute change never restarts a build: it is stored and sent to a running pipeline, and
///   otherwise waits, so dragging the volume of a failing app cannot storm the HAL.
///
/// The reducer never reads a clock: every method takes `now`, so tests drive time by hand.
public struct AudioReconciler: Sendable {

    /// The delay before each retry of a failed build: the first retry is immediate, the last
    /// waits a second. A fifth failure spends the ladder and nothing more is scheduled, because
    /// an unattended retry loop on a permanently refused tap would wake the CPU for nothing.
    public static let retryDelays: [Duration] = [
        .zero,
        .milliseconds(100),
        .milliseconds(300),
        .seconds(1),
    ]

    /// How long after a failure episode began the app still counts as `recovering`.
    public static let recoveryWindow: Duration = .seconds(3)

    /// The failure episode, for one identical configuration, that gives the configuration up.
    public static let failureEpisodesBeforeNative = 2

    private var entries   : [AudioAppIdentity: Entry] = [:]
    private var lastToken : UInt64                    = 0

    public init() {}

    // MARK: - Public API

    /// Reconciles every known app against the world and returns what AudioHost must do.
    ///
    /// `apps` is already grouped per app. Only processes that are running output count: they
    /// become the app's `processObjectIDs`, sorted so the configuration is stable, and an app
    /// with none of them is treated as absent. Actions come out ordered by bundle ID, and within
    /// an app teardown comes before build, so the result is deterministic.
    public mutating func reconcile(
        intents         : [AudioAppIdentity: AudioAppIntent],
        apps            : [AudioAppIdentity: [AudioProcessRecord]],
        outputs         : Set<String>,
        systemOutputUID : String?,
        now             : Duration
    ) -> [AudioReconcileAction] {
        var actions: [AudioReconcileAction] = []

        let identities = Set(entries.keys)
            .union(intents.keys)
            .sorted { $0.bundleID < $1.bundleID }

        for identity in identities {
            let intent = intents[identity] ?? .neutral

            let plan = Self.plan(
                for             : intent,
                records         : apps[identity] ?? [],
                outputs         : outputs,
                systemOutputUID : systemOutputUID
            )

            var entry = entries[identity] ?? Entry()

            converge(
                &entry,
                of      : identity,
                intent  : intent,
                plan    : plan,
                outputs : outputs,
                now     : now,
                into    : &actions
            )

            entries[identity] = entry.isIdle ? nil : entry
        }

        return actions
    }

    /// Reports how the build or crossfade identified by `token` ended, or that the running
    /// pipeline `token` broke (`succeeded: false` on a running token tears it down and starts a
    /// failure episode; a success report for a running token is ignored).
    ///
    /// A token that is not the current one is an obsolete build and is ignored. On success the
    /// pipeline runs; if the intent moved while it was being built, one `updateCommand` catches
    /// it up. On failure the retry ladder applies: a `scheduleRetry` names the delay, and the
    /// caller calls `reconcile` once it passes. A failed crossfade falls back to the old pipeline
    /// while retries remain; once they are spent the old pipeline is torn down too, because
    /// leaving it on the wrong output would claim a control the user did not ask for.
    public mutating func built(
        _ app     : AudioAppIdentity,
        token     : UInt64,
        succeeded : Bool,
        now       : Duration
    ) -> [AudioReconcileAction] {
        guard var entry = entries[app] else { return [] }

        var actions: [AudioReconcileAction] = []

        switch entry.state {
            case .building(let current, let configuration) where current == token:
                if succeeded {
                    entry.state = .running(token: token, configuration)
                    entry.failure = nil
                    entry.catchUpCommand(of: app, token: token, into: &actions)
                } else {
                    let outcome = entry.recordFailure(of: configuration, now: now)
                    let since   = entry.failureStart(now)

                    switch outcome {
                        case .retry(let attempts, let delay):
                            entry.state = .failed(configuration, attempts: attempts, since: since)
                            actions.append(.scheduleRetry(app, after: delay))

                        case .exhausted(let attempts):
                            entry.state = .failed(configuration, attempts: attempts, since: since)

                        case .givenUp:
                            entry.state = .native(configuration)
                    }
                }

            case .crossfading(let from, let to, let configuration) where to == token:
                if succeeded {
                    entry.state           = .running(token: to, configuration)
                    entry.crossfadeOrigin = nil
                    entry.failure         = nil
                    entry.catchUpCommand(of: app, token: to, into: &actions)
                } else {
                    let origin  = entry.crossfadeOrigin ?? configuration
                    let outcome = entry.recordFailure(of: configuration, now: now)
                    let since   = entry.failureStart(now)

                    entry.crossfadeOrigin = nil

                    switch outcome {
                        case .retry(_, let delay):
                            entry.state = .running(token: from, origin)
                            actions.append(.scheduleRetry(app, after: delay))

                        case .exhausted(let attempts):
                            actions.append(.teardown(app, token: from))
                            entry.state = .failed(configuration, attempts: attempts, since: since)

                        case .givenUp:
                            actions.append(.teardown(app, token: from))
                            entry.state = .native(configuration)
                    }
                }

            case .running(let current, let configuration) where current == token && !succeeded:
                // The service reports a live pipeline that broke (a device vanished, the tap was
                // revoked). It is a failure like any other, and the only way an identical
                // configuration can open a second episode once a wake clears the history.
                let outcome = entry.recordFailure(of: configuration, now: now)
                let since   = entry.failureStart(now)

                actions.append(.teardown(app, token: token))
                entry.commandedIntent = nil

                switch outcome {
                    case .retry(let attempts, let delay):
                        entry.state = .failed(configuration, attempts: attempts, since: since)
                        actions.append(.scheduleRetry(app, after: delay))

                    case .exhausted(let attempts):
                        entry.state = .failed(configuration, attempts: attempts, since: since)

                    case .givenUp:
                        entry.state = .native(configuration)
                }

            default:
                return []
        }

        entries[app] = entry

        return actions
    }

    /// Rebuilds the pipeline of every app whose intent needs one, keeping the intents.
    ///
    /// A wake from sleep, a device or format change and a coreaudiod restart leave the HAL
    /// objects behind the pipelines stale while every process ID, device UID and configuration
    /// still compares equal, so `reconcile` alone would see nothing to do. This is the explicit
    /// invalidation. A new environment is a fresh start: every failure episode and every `native`
    /// fallback is forgotten, and a failed or `native` app is built again like a running one.
    /// It is not a failure itself. A crossfade in flight restarts directly on its target.
    public mutating func environmentInvalidated(now: Duration) -> [AudioReconcileAction] {
        var actions: [AudioReconcileAction] = []

        let identities = entries.keys.sorted { $0.bundleID < $1.bundleID }

        for identity in identities {
            guard
                var entry = entries[identity],
                let intent = entry.intent
            else { continue }

            let configuration: AudioPipelineConfiguration

            switch entry.state {
                case .building(_, let building):
                    configuration = building

                case .running(_, let running):
                    configuration = running

                case .crossfading(_, _, let target):
                    configuration = target

                case .failed(let failed, _, _):
                    configuration = failed

                case .native(let fallback):
                    configuration = fallback

                case .none:
                    continue
            }

            tearDown(&entry, of: identity, into: &actions)
            entry.forgetFailures()
            issueBuild(&entry, of: identity, configuration: configuration, intent: intent, into: &actions)

            entries[identity] = entry
        }

        return actions
    }

    /// Returns where the pipeline of `app` stands; `.none` for an app the reducer does not track.
    public func state(of app: AudioAppIdentity) -> AudioPipelineState {
        entries[app]?.state ?? .none
    }

    /// Returns how well the intent of `app` is being honoured at `now`.
    ///
    /// No pipeline needed is `native`; a running pipeline, or a crossfade whose old pipeline is
    /// still live, is `applied`. A build that has not failed yet is `recovering`, because the
    /// control is not live yet. After a failure the app is `recovering` for three seconds from the
    /// episode start and `notApplied` after; a `native` fallback, and a non-neutral intent with
    /// no output to render to, are `notApplied`.
    public func enforcement(of app: AudioAppIdentity, now: Duration) -> AudioAppEnforcement {
        guard let entry = entries[app] else { return .native }

        switch entry.state {
            case .none:
                return entry.isBlockedByNoOutput ? .notApplied : .native

            case .native:
                return .notApplied

            case .running, .crossfading:
                return .applied

            case .building:
                guard let failure = entry.failure else { return .recovering }

                return Self.enforcement(failedSince: failure.since, now: now)

            case .failed(_, _, let since):
                return Self.enforcement(failedSince: since, now: now)
        }
    }

    // MARK: - Planning

    /// Plan is what the world asks for one app, before comparing it with what exists.
    private enum Plan: Equatable {

        /// No pipeline is needed: a neutral intent, or no process producing output.
        case idle

        /// A pipeline is needed but there is no device to render to.
        case blocked

        case pipeline(AudioPipelineConfiguration)
    }

    private static func plan(
        for intent      : AudioAppIntent,
        records         : [AudioProcessRecord],
        outputs         : Set<String>,
        systemOutputUID : String?
    ) -> Plan {
        let processObjectIDs = records
            .filter(\.isRunningOutput)
            .map(\.objectID)
            .sorted()

        guard !intent.isNeutral, !processObjectIDs.isEmpty else { return .idle }

        var effectiveOutputs = intent.outputUIDs.filter { outputs.contains($0) }

        if effectiveOutputs.isEmpty, let systemOutputUID {
            effectiveOutputs = [systemOutputUID]
        }

        guard !effectiveOutputs.isEmpty else { return .blocked }

        return .pipeline(
            AudioPipelineConfiguration(
                processObjectIDs : processObjectIDs,
                outputUIDs       : effectiveOutputs,
                streamTap        : effectiveOutputs.count == 1
            )
        )
    }

    /// A crossfade needs a reason (the outputs changed) and a source that can still play (every
    /// old output exists). A change in the processes alone has no output to hand over to.
    private static func canCrossfade(
        from old : AudioPipelineConfiguration,
        to new   : AudioPipelineConfiguration,
        outputs  : Set<String>
    ) -> Bool {
        let outputsChanged = old.outputUIDs != new.outputUIDs || old.streamTap != new.streamTap

        return outputsChanged && old.outputUIDs.allSatisfy { outputs.contains($0) }
    }

    private static func enforcement(
        failedSince : Duration,
        now         : Duration
    ) -> AudioAppEnforcement {
        now - failedSince < recoveryWindow ? .recovering : .notApplied
    }

    // MARK: - Convergence

    /// Moves one app's entry toward its plan, appending the actions that get it there.
    private mutating func converge(
        _ entry      : inout Entry,
        of identity  : AudioAppIdentity,
        intent       : AudioAppIntent,
        plan         : Plan,
        outputs      : Set<String>,
        now          : Duration,
        into actions : inout [AudioReconcileAction]
    ) {
        entry.intent              = intent
        entry.isBlockedByNoOutput = plan == .blocked

        guard case .pipeline(let target) = plan else {
            tearDown(&entry, of: identity, into: &actions)

            entry.state           = .none
            entry.crossfadeOrigin = nil
            entry.commandedIntent = nil
            entry.forgetFailures()

            return
        }

        // A failure episode ends when the configuration changes, and the verdict of an earlier
        // episode ("native") ends with it. The intent is deliberately not a trigger: gain and
        // mute are not part of the configuration, and a slider dragged at display rate must not
        // restart builds on an app the HAL keeps refusing.
        if entry.episodeConfiguration != target {
            entry.forgetFailures()
        }

        switch entry.state {
            case .none:
                issueBuild(&entry, of: identity, configuration: target, intent: intent, into: &actions)

            case .building(let token, let configuration):
                guard configuration != target else { return }

                actions.append(.teardown(identity, token: token))
                issueBuild(&entry, of: identity, configuration: target, intent: intent, into: &actions)

            case .running(let token, let configuration):
                if configuration == target {
                    entry.catchUpCommand(of: identity, token: token, into: &actions)
                } else if entry.isWaitingForRetry(at: now) {
                    return
                } else if Self.canCrossfade(from: configuration, to: target, outputs: outputs) {
                    issueCrossfade(
                        &entry,
                        of            : identity,
                        from          : token,
                        origin        : configuration,
                        configuration : target,
                        intent        : intent,
                        into          : &actions
                    )
                } else {
                    actions.append(.teardown(identity, token: token))
                    issueBuild(&entry, of: identity, configuration: target, intent: intent, into: &actions)
                }

            case .crossfading(_, _, let configuration):
                guard configuration != target else { return }

                // The old configuration is not tracked well enough to crossfade again from a
                // crossfade in flight, so the change tears down both ends and rebuilds: a brief
                // audio gap, accepted because it takes a second change inside one build.

                tearDown(&entry, of: identity, into: &actions)
                issueBuild(&entry, of: identity, configuration: target, intent: intent, into: &actions)

            case .failed(let configuration, _, _):
                if configuration == target, entry.failure != nil {
                    guard entry.isRetryDue(at: now) else { return }
                }

                issueBuild(&entry, of: identity, configuration: target, intent: intent, into: &actions)

            case .native(let configuration):
                let isGivenUp = configuration == target
                    && entry.failedEpisodes >= Self.failureEpisodesBeforeNative

                guard !isGivenUp else { return }

                issueBuild(&entry, of: identity, configuration: target, intent: intent, into: &actions)
        }
    }

    private mutating func issueBuild(
        _ entry       : inout Entry,
        of identity   : AudioAppIdentity,
        configuration : AudioPipelineConfiguration,
        intent        : AudioAppIntent,
        into actions  : inout [AudioReconcileAction]
    ) {
        let token = nextToken()

        entry.state            = .building(token: token, configuration)
        entry.commandedIntent  = intent
        entry.crossfadeOrigin  = nil
        entry.failure?.retryAt = nil

        actions.append(.build(identity, token: token, configuration, intent))
    }

    private mutating func issueCrossfade(
        _ entry       : inout Entry,
        of identity   : AudioAppIdentity,
        from          : UInt64,
        origin        : AudioPipelineConfiguration,
        configuration : AudioPipelineConfiguration,
        intent        : AudioAppIntent,
        into actions  : inout [AudioReconcileAction]
    ) {
        let token = nextToken()

        entry.state            = .crossfading(from: from, to: token, configuration)
        entry.commandedIntent  = intent
        entry.crossfadeOrigin  = origin
        entry.failure?.retryAt = nil

        actions.append(.crossfade(identity, from: from, to: token, configuration, intent))
    }

    /// Appends a teardown for every live token of the entry: the one pipeline of a running or
    /// building state, both ends of a crossfade.
    private func tearDown(
        _ entry      : inout Entry,
        of identity  : AudioAppIdentity,
        into actions : inout [AudioReconcileAction]
    ) {
        switch entry.state {
            case .building(let token, _), .running(let token, _):
                actions.append(.teardown(identity, token: token))

            case .crossfading(let from, let to, _):
                actions.append(.teardown(identity, token: from))
                actions.append(.teardown(identity, token: to))

            case .none, .failed, .native:
                break
        }
    }

    private mutating func nextToken() -> UInt64 {
        lastToken += 1

        return lastToken
    }

    // MARK: - Entry

    /// Failure is one failure episode in progress: when it began, how many builds have failed
    /// in it, and when the next retry is due (nil while a build is in flight or the ladder is
    /// spent).
    private struct Failure: Sendable {

        let since    : Duration
        var attempts : Int
        var retryAt  : Duration?
    }

    /// FailureOutcome is what recording one more failed build decided.
    private enum FailureOutcome {

        case retry(attempts: Int, after: Duration)
        case exhausted(attempts: Int)
        case givenUp
    }

    /// Entry is everything the reducer remembers about one app.
    private struct Entry: Sendable {

        var state                : AudioPipelineState             = .none
        var intent               : AudioAppIntent?
        var commandedIntent      : AudioAppIntent?
        var crossfadeOrigin      : AudioPipelineConfiguration?
        var isBlockedByNoOutput  : Bool                           = false
        var episodeConfiguration : AudioPipelineConfiguration?
        var failedEpisodes       : Int                            = 0
        var failure              : Failure?

        var isIdle: Bool {
            if case .none = state { return !isBlockedByNoOutput }

            return false
        }

        func failureStart(_ fallback: Duration) -> Duration {
            failure?.since ?? fallback
        }

        func isRetryDue(at now: Duration) -> Bool {
            guard let retryAt = failure?.retryAt else { return false }

            return retryAt <= now
        }

        /// A running pipeline whose last crossfade failed waits for its retry, not for the next
        /// reconcile call.
        func isWaitingForRetry(at now: Duration) -> Bool {
            failure != nil && !isRetryDue(at: now)
        }

        mutating func forgetFailures() {
            failure              = nil
            failedEpisodes       = 0
            episodeConfiguration = nil
        }

        /// Sends the pipeline the intent it has not been told yet, if any.
        mutating func catchUpCommand(
            of identity  : AudioAppIdentity,
            token        : UInt64,
            into actions : inout [AudioReconcileAction]
        ) {
            guard let intent, commandedIntent != intent else { return }

            commandedIntent = intent
            actions.append(.updateCommand(identity, token: token, intent))
        }

        /// Records one failed build of `configuration`, starting an episode if none is open.
        mutating func recordFailure(
            of configuration : AudioPipelineConfiguration,
            now              : Duration
        ) -> FailureOutcome {
            var current: Failure

            // History belongs to one configuration: a failure of another one starts afresh.
            if episodeConfiguration != configuration { forgetFailures() }

            if let open = failure {
                current = open
            } else {
                failedEpisodes      += 1
                episodeConfiguration = configuration
                current              = Failure(since: now, attempts: 0, retryAt: nil)
            }

            guard failedEpisodes < AudioReconciler.failureEpisodesBeforeNative else {
                failure = nil

                return .givenUp
            }

            current.attempts += 1

            guard current.attempts <= AudioReconciler.retryDelays.count else {
                current.retryAt = nil
                failure         = current

                return .exhausted(attempts: current.attempts)
            }

            let delay = AudioReconciler.retryDelays[current.attempts - 1]

            current.retryAt = now + delay
            failure         = current

            return .retry(attempts: current.attempts, after: delay)
        }
    }
}
