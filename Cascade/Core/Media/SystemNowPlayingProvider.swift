//
//  SystemNowPlayingProvider.swift
//  Cascade
//

import AppKit
import CascadeKit
import Foundation
import Observation

/// SystemNowPlayingProvider observes native Music and Spotify events. It owns
/// no periodic polling, never launches a player while reading, and performs all AppleEvent
/// IO and artwork decoding on a separate actor. Commands use their own worker:
/// synchronous metadata replies must never delay a user's playback action.
/// A source has at most one read in flight; bursts coalesce into one refresh.
/// Playback events and completed commands get two bounded follow-up reads to
/// cover Music acknowledging a transition before its scripting state settles.
/// The state a player's notification carries is applied at once, with no
/// AppleEvent round trip, and outranks reads begun just after it.
@Observable
@MainActor
final class SystemNowPlayingProvider: NowPlayingProviding {

    private(set) var status: NowPlayingProviderStatus = .stopped

    @ObservationIgnored
    private let reader        : any ScriptableMusicReading
    @ObservationIgnored
    private let commandSender : any ScriptableMusicCommandSending
    @ObservationIgnored
    private let resolveTargets: @MainActor () -> [ScriptableMusicSource: ScriptablePlayerTarget]
    @ObservationIgnored
    private let preferences   : UserDefaults

    @ObservationIgnored
    private var continuation: AsyncStream<NowPlayingSnapshot?>.Continuation?

    @ObservationIgnored
    private var distributedObservers: [NSObjectProtocol] = []
    @ObservationIgnored
    private var workspaceObservers  : [NSObjectProtocol] = []

    @ObservationIgnored
    private var targets      : [ScriptableMusicSource: ScriptablePlayerTarget] = [:]
    @ObservationIgnored
    private var tasks        : [ScriptableMusicSource: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var settlingTasks: [ScriptableMusicSource: Task<Void, Never>] = [:]
    @ObservationIgnored
    private var errors       : [ScriptableMusicSource: ScriptableMusicError] = [:]
    @ObservationIgnored
    private var revisions     = NowPlayingRefreshRevisions()
    @ObservationIgnored
    private var selection     = NowPlayingSourceSelection()
    @ObservationIgnored
    private var announcements: [ScriptableMusicSource: NowPlayingAnnouncement] = [:]

    @ObservationIgnored
    private var lastPublished     : NowPlayingSnapshot?
    @ObservationIgnored
    private var generation        : UInt64 = 0
    @ObservationIgnored
    private var isRequestingAccess = false

    init(
        reader        : any ScriptableMusicReading = ScriptableMusicAppleEventReader(),
        commandSender : any ScriptableMusicCommandSending = ScriptableMusicAppleEventReader(),
        preferences   : UserDefaults = .standard,
        resolveTargets: @escaping @MainActor () -> [ScriptableMusicSource: ScriptablePlayerTarget] = {
            SystemNowPlayingProvider.runningTargets()
        }
    ) {
        self.reader         = reader
        self.commandSender  = commandSender
        self.preferences    = preferences
        self.resolveTargets = resolveTargets
    }

    func start() -> AsyncStream<NowPlayingSnapshot?> {
        stop()

        let pair = AsyncStream<NowPlayingSnapshot?>.makeStream(bufferingPolicy: .bufferingNewest(1))
        continuation = pair.continuation
        status       = .monitoring
        pair.continuation.yield(nil)

        let activeGeneration = generation
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == activeGeneration else { return }

                self.stop()
            }
        }

        observePlayers()
        reconcileRunningPlayers(refreshExisting: true)
        return pair.stream
    }

    /// stop invalidates all completions before cancelling work. Late AppleEvent
    /// replies can finish on the worker but cannot revive the activity or retain
    /// source images through this provider after its stream has ended.
    func stop() {
        generation &+= 1

        distributedObservers.forEach { DistributedNotificationCenter.default().removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        distributedObservers.removeAll()
        workspaceObservers.removeAll()

        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        settlingTasks.values.forEach { $0.cancel() }
        settlingTasks.removeAll()

        targets.removeAll()
        errors.removeAll()
        announcements.removeAll()
        revisions.reset()
        selection     = NowPlayingSourceSelection()
        lastPublished = nil

        continuation?.finish()
        continuation = nil
        status       = .stopped

        let reader = reader
        Task { await reader.reset() }
    }

    /// requestAccess runs at launch and remains available from the menu. Apple
    /// requires a running target for Automation consent. First-time startup
    /// setup can launch an installed player in the background; metadata reads
    /// never launch applications. A saved attempt prevents reopening idle
    /// players on every subsequent Cascade launch, without caching permission.
    /// A player launched only for consent is quit again once the prompt is
    /// answered, unless the user has brought it forward in the meantime.
    func requestAccess(includeInstalledPlayers: Bool = false) async {
        guard !isRequestingAccess else { return }

        isRequestingAccess = true
        defer { isRequestingAccess = false }

        let activeGeneration = generation
        for source in ScriptableMusicSource.allCases {
            guard generation == activeGeneration,
                  continuation != nil,
                  !Task.isCancelled
            else { return }

            let attemptKey = "startupAutomationRequested.\(source.bundleIdentifier)"
            var target     = resolveTargets()[source]

            var launchedForConsent: NSRunningApplication?
            defer {
                if let launchedForConsent,
                   launchedForConsent.isHidden,
                   !launchedForConsent.isActive {
                    launchedForConsent.terminate()
                }
            }

            if target == nil,
               includeInstalledPlayers,
               !preferences.bool(forKey: attemptKey),
               let url = NSWorkspace.shared.urlForApplication(
                   withBundleIdentifier: source.bundleIdentifier
               ) {
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = false
                configuration.hides     = true

                do {
                    let application = try await NSWorkspace.shared.openApplication(
                        at           : url,
                        configuration: configuration
                    )
                    launchedForConsent = application
                    guard generation == activeGeneration,
                          continuation != nil,
                          !Task.isCancelled
                    else { return }

                    target = ScriptablePlayerTarget(
                        source           : source,
                        processIdentifier: application.processIdentifier
                    )
                } catch {
                    guard generation == activeGeneration,
                          continuation != nil,
                          !Task.isCancelled
                    else { return }

                    errors[source] = Self.sourceError(error)
                    continue
                }
            }

            guard let target else { continue }

            do {
                try await reader.requestAccess(target)
                guard generation == activeGeneration,
                      continuation != nil,
                      !Task.isCancelled
                else { return }

                preferences.set(true, forKey: attemptKey)
                errors[source] = nil

                // A player launched only for consent is about to quit and has
                // nothing playing, so reading it would be wasted AppleEvents.
                if launchedForConsent == nil {
                    reconcileRunningPlayers(refreshExisting: false)
                    requestRefresh(source)
                }
            } catch {
                guard generation == activeGeneration,
                      continuation != nil,
                      !Task.isCancelled
                else { return }

                errors[source] = Self.sourceError(error)
                if case .permissionRequired = errors[source] {
                    preferences.set(true, forKey: attemptKey)
                }
            }
        }

        updateStatus()
    }

    /// send preserves the provider protocol for callers that act on its current
    /// selection. UI actions use the matching overload with their rendered track.
    func send(_ command: MediaCommand) async throws {
        guard let snapshot = selection.current else {
            throw ScriptableMusicError.unavailable("Nessun lettore compatibile è attivo.")
        }

        try await send(command, matching: snapshot)
    }

    /// send rejects an action captured by a previous track or source before
    /// dispatch. Validation and target capture share the main actor with no
    /// suspension between them, so a delayed UI task cannot control a new song.
    func send(
        _ command        : MediaCommand,
        matching expected: NowPlayingSnapshot
    ) async throws {
        guard selection.matches(expected) else { throw ScriptableMusicError.trackChanged }
        guard continuation != nil,
              let snapshot = selection.current,
              let source = ScriptableMusicSource.allCases.first(
                  where: { $0.bundleIdentifier == snapshot.sourceBundleIdentifier }
              ),
              let target = targets[source],
              Self.supports(command, capabilities: snapshot.capabilities)
        else { throw ScriptableMusicError.unavailable("Nessun lettore compatibile è attivo.") }

        let activeGeneration = generation
        do {
            try await commandSender.send(
                command,
                to           : target,
                expectedTrack: snapshot.trackIdentifier
            )
        } catch {
            if generation == activeGeneration, targets[source] == target {
                errors[source] = Self.sourceError(error)
                requestRefresh(source)
                updateStatus()
            }
            throw error
        }

        guard generation == activeGeneration, targets[source] == target else { return }

        refreshAfterPlaybackChange(source)
    }

    private func observePlayers() {
        for source in ScriptableMusicSource.allCases {
            let observer = DistributedNotificationCenter.default().addObserver(
                forName: source.notificationName,
                object : nil,
                queue  : .main
            ) { [weak self] notification in
                let state = ScriptablePlaybackState(playerInfo: notification.userInfo)
                Task { @MainActor [weak self] in
                    self?.receivePlayerNotification(state, from: source)
                }
            }
            distributedObservers.append(observer)
        }

        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification
        ]
        for name in names {
            let observer = NSWorkspace.shared.notificationCenter.addObserver(
                forName: name,
                object : nil,
                queue  : .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.continuation != nil else { return }

                    let refreshExisting = name == NSWorkspace.didWakeNotification
                        || name == NSWorkspace.sessionDidBecomeActiveNotification
                    self.reconcileRunningPlayers(refreshExisting: refreshExisting)
                }
            }
            workspaceObservers.append(observer)
        }
    }

    /// receivePlayerNotification publishes the announced playback before any
    /// read, so pausing from the keyboard releases the notch immediately.
    func receivePlayerNotification(
        _ state    : ScriptablePlaybackState?,
        from source: ScriptableMusicSource
    ) {
        guard continuation != nil else { return }

        reconcileRunningPlayers(refreshExisting: false)
        if let state, targets[source] != nil {
            let announcement = NowPlayingAnnouncement(state: state, time: .now)
            announcements[source] = announcement
            selection.announce(announcement, from: source)
            publish()
        }

        refreshAfterPlaybackChange(source)
    }

    private func reconcileRunningPlayers(refreshExisting: Bool) {
        let running       = resolveTargets()
        var removedPlayer = false

        for source in ScriptableMusicSource.allCases {
            guard let target = running[source] else {
                if targets[source] != nil {
                    remove(source)
                    removedPlayer = true
                }
                continue
            }

            if targets[source] != target {
                remove(source)
                targets[source] = target
                requestRefresh(source)
            } else if refreshExisting {
                requestRefresh(source)
            }
        }

        publish(repeatingEmpty: removedPlayer)
        updateStatus()
    }

    private func remove(_ source: ScriptableMusicSource) {
        tasks[source]?.cancel()
        tasks[source] = nil
        settlingTasks[source]?.cancel()
        settlingTasks[source] = nil

        targets[source]       = nil
        errors[source]        = nil
        announcements[source] = nil
        revisions.remove(source)
        selection.receive(nil, from: source)

        let reader = reader
        Task { await reader.discardArtwork(source) }
    }

    /// refreshAfterPlaybackChange exists because an AppleEvent reply or
    /// notification can precede the new playable track.
    /// Reconcile after that transition even if Music emits no further event.
    /// New events replace this finite task; stop and process removal cancel it.
    private func refreshAfterPlaybackChange(_ source: ScriptableMusicSource) {
        guard continuation != nil, let target = targets[source] else { return }

        requestRefresh(source)
        settlingTasks[source]?.cancel()

        let activeGeneration = generation
        settlingTasks[source] = Task { [weak self] in
            for delay in [Duration.milliseconds(250), .milliseconds(750)] {
                // A slow read may be replaced after a revision mismatch. Drain
                // that work before spending the next confirmation, otherwise
                // all follow-ups can coalesce into one intermediate reply.
                while let pendingRead = self?.tasks[source] {
                    await pendingRead.value
                    guard let self,
                          !Task.isCancelled,
                          self.generation == activeGeneration,
                          self.targets[source] == target
                    else { return }
                }

                do { try await Task.sleep(for: delay) } catch { return }
                guard let self,
                      !Task.isCancelled,
                      self.generation == activeGeneration,
                      self.targets[source] == target
                else { return }

                self.requestRefresh(source)
            }

            self?.settlingTasks[source] = nil
        }
    }

    private func requestRefresh(_ source: ScriptableMusicSource) {
        guard continuation != nil, targets[source] != nil else { return }

        let revision = revisions.request(source)
        guard tasks[source] == nil else { return }

        beginRefresh(source, revision: revision)
    }

    private func beginRefresh(
        _ source: ScriptableMusicSource,
        revision: UInt64
    ) {
        guard let target = targets[source] else { return }

        let activeGeneration = generation
        let reader           = reader
        let startedAt        = ContinuousClock.now

        tasks[source] = Task { [weak self] in
            let result: Result<NowPlayingSnapshot?, Error>
            do { result = .success(try await reader.read(target)) }
            catch { result = .failure(error) }

            guard let self,
                  !Task.isCancelled,
                  self.generation == activeGeneration,
                  self.targets[source] == target
            else { return }

            self.tasks[source] = nil
            guard self.revisions.accepts(revision, for: source) else {
                if let currentRevision = self.revisions.current(source) {
                    self.beginRefresh(source, revision: currentRevision)
                }
                return
            }

            switch result {
                case .success(let snapshot):
                    self.errors[source] = nil
                    self.selection.receive(
                        self.announcements[source].map {
                            $0.applied(to: snapshot, startedAt: startedAt)
                        } ?? snapshot,
                        from: source
                    )

                case .failure(let error):
                    self.errors[source] = Self.sourceError(error)
                    self.selection.receive(nil, from: source)
            }

            self.publish()
            self.updateStatus()
        }
    }

    /// publish yields only changes, except that a player quitting repeats an
    /// empty selection a stop had already emptied: observers learn from it
    /// that the session is over, not merely stopped.
    private func publish(repeatingEmpty: Bool = false) {
        let snapshot = selection.current
        guard snapshot != lastPublished || (repeatingEmpty && snapshot == nil) else { return }

        lastPublished = snapshot
        continuation?.yield(snapshot)
    }

    private func updateStatus() {
        guard continuation != nil else { return }

        if selection.current != nil {
            status = .monitoring
            return
        }

        for source in ScriptableMusicSource.allCases {
            if case .permissionRequired = errors[source] {
                status = .permissionRequired(
                    errors[source]?.localizedDescription ?? "Consenti l'accesso al lettore musicale."
                )
                return
            }
        }

        if let error = ScriptableMusicSource.allCases.compactMap({ errors[$0] }).first {
            status = .unavailable(error.localizedDescription)
        } else {
            status = .monitoring
        }
    }

    private static func runningTargets() -> [ScriptableMusicSource: ScriptablePlayerTarget] {
        var result: [ScriptableMusicSource: ScriptablePlayerTarget] = [:]
        for source in ScriptableMusicSource.allCases {
            if let application = NSRunningApplication
                .runningApplications(withBundleIdentifier: source.bundleIdentifier)
                .first(where: { !$0.isTerminated && $0.isFinishedLaunching }) {
                result[source] = ScriptablePlayerTarget(
                    source           : source,
                    processIdentifier: application.processIdentifier
                )
            }
        }

        return result
    }

    private static func sourceError(_ error: Error) -> ScriptableMusicError {
        (error as? ScriptableMusicError) ?? .unavailable(error.localizedDescription)
    }

    private static func supports(
        _ command   : MediaCommand,
        capabilities: MediaCommandCapabilities
    ) -> Bool {
        switch command {
            case .togglePlayback: capabilities.contains(.togglePlayback)
            case .previousTrack: capabilities.contains(.previousTrack)
            case .nextTrack: capabilities.contains(.nextTrack)
            case .seek: capabilities.contains(.seek)
            case .toggleFavorite: capabilities.contains(.favorite)
        }
    }
}
