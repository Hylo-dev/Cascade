//
//  NowPlayingBehaviorChecks.swift
//  Cascade
//

#if NOW_PLAYING_TESTS
import AppKit
import CascadeKit
import CoreServices
import Foundation

@main
private enum NowPlayingBehaviorChecks {
    static func main() async throws {
        try await checkImmediatePresentation()
        try checkMetadata()
        try checkSelection()
        try checkDelayedCommands()
        try checkRefreshRaces()
        try checkArtworkBounds()
        try checkDescriptorDecoding()
        try await checkCommandsDuringRefresh()
        try await checkPreviousTrackSettles()
        try await checkPreviousTrackSettlesAfterSlowRead()
        try checkPlayerInfoParsing()
        try await checkAnnouncedPauseOutranksStaleReads()
        try await checkQuittingRepeatsTheEmptySelection()
        print("Now Playing behavior checks passed")
        if CommandLine.arguments.contains("--probe") { await probeAuthorizedPlayers() }
    }

    private static func checkImmediatePresentation() async throws {
        let now = Date.now
        func track(playing: Bool, position: Double = 20, id: String = "A") -> NowPlayingSnapshot {
            NowPlayingSnapshot(sourceBundleIdentifier: "com.apple.Music", title: id, artist: "Artist",
                               isPlaying: playing, duration: 180, elapsed: position, timestamp: now,
                               capabilities: [.togglePlayback, .seek, .favorite, .nextTrack, .previousTrack], trackIdentifier: id, isFavorite: false)
        }
        let playing = track(playing: true)
        let ui = MusicPlaybackPresentation(snapshot: playing, confirmationTimeout: .milliseconds(20))
        let pause = ui.begin(.togglePlayback, capability: .togglePlayback, at: now)!
        try expect(!ui.displayed.isPlaying && ui.confirmed.isPlaying, "Pause feedback must be synchronous and independent of the real player")
        try expect(ui.displayed.position(at: now.addingTimeInterval(10)) == 20, "Pending pause must freeze progress immediately")
        ui.receive(playing)
        try expect(!ui.displayed.isPlaying, "An older read must not flash the previous playback state")
        ui.receive(track(playing: false))
        ui.succeed(pause)
        try expect(ui.pendingCapability == nil && !ui.displayed.isPlaying, "Confirmation must release pending feedback")
        let resume = ui.begin(.togglePlayback, capability: .togglePlayback, at: now)!
        try expect(ui.displayed.isPlaying, "Resume must change the icon without waiting for IO")
        ui.fail(resume)
        try expect(!ui.displayed.isPlaying && ui.commandError != nil, "Failed commands must restore the confirmed player state")
        let seek = ui.begin(.seek(90), capability: .seek, at: now)!
        try expect(ui.displayed.elapsed == 90, "Seek must retain the committed position while waiting")
        ui.succeed(seek)
        try await Task.sleep(for: .milliseconds(60))
        try expect(ui.displayed.elapsed == 20 && ui.pendingCapability == nil, "Missing confirmation must never leave invented playback indefinitely")
        let old = ui.begin(.togglePlayback, capability: .togglePlayback, at: now)!
        ui.receive(track(playing: true, id: "B"))
        let current = ui.begin(.togglePlayback, capability: .togglePlayback, at: now)!
        ui.fail(old)
        try expect(ui.pendingCapability == .togglePlayback && !ui.displayed.isPlaying, "Late completions must not undo a new track's intent")
        ui.fail(current)
        try expect(ui.displayed.title == "B" && ui.displayed.isPlaying, "Rollback must preserve the newest track")
    }

    private static func checkMetadata() throws {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let track = ScriptableTrackMetadata(
            identifier: "real-track",
            title     : " Song ",
            artist    : " Artist ",
            duration  : 180_000,
            favorite  : true
        )
        let spotify = track.snapshot(
            source     : .spotify,
            state      : .paused,
            elapsed    : 23,
            timestamp  : timestamp,
            artworkData: nil
        )
        try expect(spotify?.duration == 180, "Spotify duration must convert milliseconds to seconds")
        try expect(spotify?.position(at: timestamp.addingTimeInterval(9)) == 23, "Paused metadata must not advance")
        try expect(spotify?.isFavorite == nil, "Spotify must not advertise an unsupported favorite state")
        try expect(spotify?.capabilities.contains(.favorite) == false, "Spotify must not advertise unsupported favorite controls")
        try expect(spotify?.title == "Song", "Metadata must normalize outer whitespace")
        let music = track.snapshot(source: .music, state: .playing, elapsed: 23, timestamp: timestamp, artworkData: nil)
        try expect(music?.duration == 180_000, "Music duration already uses seconds")
        try expect(music?.isFavorite == true && music?.capabilities.contains(.favorite) == true, "Music favorite state must come from the player")
        try expect(track.snapshot(source: .music, state: .stopped, elapsed: 0, timestamp: timestamp, artworkData: nil) == nil, "Stopped playback must end the activity")
        let empty = ScriptableTrackMetadata(identifier: nil, title: " \n", artist: "", duration: .nan, favorite: nil)
        try expect(empty.snapshot(source: .music, state: .playing, elapsed: 0, timestamp: timestamp, artworkData: nil) == nil, "Missing titles must not create invented music")
        let live = ScriptableTrackMetadata(identifier: nil, title: "Radio", artist: "", duration: .infinity, favorite: nil)
        let stream = live.snapshot(source: .music, state: .playing, elapsed: .nan, timestamp: timestamp, artworkData: nil)
        try expect(stream?.duration == nil && stream?.elapsed == 0, "Invalid timing must stay out of progress calculations")
        try expect(stream?.capabilities.contains(.seek) == false, "Unknown duration must not promise seeking")
        let scrubbing = track.snapshot(source: .music, state: .scrubbing, elapsed: 23, timestamp: timestamp, artworkData: nil)
        try expect(scrubbing?.isPlaying == true && scrubbing?.playbackRate == 0, "Fast-forward or rewind must remain active without inventing their unknown playback rate")
    }

    private static func checkSelection() throws {
        var selection = NowPlayingSourceSelection()
        let first = sample(source: .music, title: "Music", playing: true)
        let second = sample(source: .spotify, title: "Spotify", playing: false)
        selection.receive(first, from: .music)
        selection.receive(second, from: .spotify)
        try expect(selection.current?.title == "Music", "A paused source must not steal activity from a playing source")
        selection.receive(sample(source: .spotify, title: "New Spotify", playing: true), from: .spotify)
        try expect(selection.current?.title == "New Spotify", "A newly playing source must win selection")
        selection.receive(nil, from: .spotify)
        try expect(selection.current?.title == "Music", "Quitting the selected player must reveal another active source")
        selection.receive(nil, from: .music)
        try expect(selection.current == nil, "Quitting all players must dismiss the activity")
    }

    private static func checkRefreshRaces() throws {
        var revisions = NowPlayingRefreshRevisions()
        let beforeStop = revisions.request(.music)
        let newer = revisions.request(.music)
        try expect(!revisions.accepts(beforeStop, for: .music), "A late response must not overwrite a newer playback event")
        try expect(revisions.accepts(newer, for: .music), "The newest source response must be accepted")
        revisions.remove(.music)
        try expect(!revisions.accepts(newer, for: .music), "Source termination must invalidate in-flight reads")
        let restarted = revisions.request(.music)
        try expect(!revisions.accepts(beforeStop, for: .music) && revisions.accepts(restarted, for: .music), "A restarted source must not accept results from its old process")
        revisions.reset()
        try expect(!revisions.accepts(restarted, for: .music), "Stopping the provider must invalidate all unfinished reads")
    }

    private static func checkDelayedCommands() throws {
        var selection = NowPlayingSourceSelection()
        let captured = sample(source: .music, title: "Track A", playing: true, identifier: "A")
        selection.receive(captured, from: .music)
        try expect(selection.matches(captured), "A command captured from the current track must remain valid")
        selection.receive(sample(source: .music, title: "Track A", playing: true, identifier: "B"), from: .music)
        try expect(!selection.matches(captured), "A delayed command must reject another track even when its title and artist match")
        selection.receive(sample(source: .spotify, title: "Track A", playing: true, identifier: "A"), from: .spotify)
        try expect(!selection.matches(captured), "A delayed command must not follow selection into another player")
        selection.receive(nil, from: .spotify)
        let fallback = sample(source: .music, title: "Radio A", playing: true)
        selection.receive(fallback, from: .music)
        try expect(selection.matches(fallback), "Sources without stable identifiers must match current title and artist")
        selection.receive(sample(source: .music, title: "Radio B", playing: true), from: .music)
        try expect(!selection.matches(fallback), "Fallback identity must reject a changed title")
        selection.receive(nil, from: .music)
        try expect(!selection.matches(fallback), "A command captured before source termination must be rejected")
    }

    private static func checkArtworkBounds() throws {
        try expect(ScriptableMusicArtwork.thumbnail(Data(repeating: 0, count: 4 * 1_024 * 1_024 + 1)) == nil, "Oversized artwork must be rejected before decoding")
        try expect(ScriptableMusicArtwork.thumbnail(Data("invalid image".utf8)) == nil, "Malformed artwork must not reach the UI")
        for value in ["file:///etc/passwd", "http://i.scdn.co/image/a", "https://i.scdn.co.attacker.example/a", "https://user:password@i.scdn.co/image/a"] {
            guard let url = URL(string: value) else { throw CheckFailure.failed("Invalid URL fixture") }
            try expect(!ScriptableMusicArtwork.permits(url), "Artwork URLs must be limited to trusted HTTPS image CDNs")
        }
        guard let valid = URL(string: "https://i.scdn.co/image/a") else { throw CheckFailure.failed("Invalid URL fixture") }
        try expect(ScriptableMusicArtwork.permits(valid), "Normal Spotify album artwork must remain supported")
    }

    private static func checkDescriptorDecoding() throws {
        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(string: "Real title"), forKeyword: 0x706E616D)
        record.setDescriptor(NSAppleEventDescriptor(string: "Real artist"), forKeyword: 0x70417274)
        record.setDescriptor(NSAppleEventDescriptor(string: "ABC123"), forKeyword: 0x70504953)
        record.setDescriptor(NSAppleEventDescriptor(double: 182.25), forKeyword: 0x70447572)
        record.setDescriptor(NSAppleEventDescriptor(boolean: true), forKeyword: 0x704C6F76)
        let metadata = ScriptableMusicDescriptorDecoder.metadata(record, source: .music)
        try expect(metadata.title == "Real title" && metadata.artist == "Real artist", "AppleEvent record fields must preserve title and artist")
        try expect(metadata.identifier == "ABC123" && metadata.duration == 182.25 && metadata.favorite == true, "AppleEvent identity, duration and favorite must decode from native descriptors")
        let missing = ScriptableMusicDescriptorDecoder.metadata(NSAppleEventDescriptor.null(), source: .music)
        try expect(missing.title.isEmpty && missing.favorite == nil && missing.duration == nil, "An absent native record must not invent known values")
        try expect(ScriptableMusicDescriptorDecoder.playbackState(0x6B505350) == .playing, "Native playing enum must decode correctly")
        try expect(ScriptableMusicDescriptorDecoder.playbackState(0x6B505353) == .stopped, "Native stopped enum must end the session")
        try expect(ScriptableMusicDescriptorDecoder.playbackState(0x6B505370) == .paused, "Native paused enum is case-sensitive")
    }

    /// checkCommandsDuringRefresh holds a metadata reply open while delivering
    /// play. It catches commands queued behind reads and stale read publication.
    private static func checkCommandsDuringRefresh() async throws {
        let paused = sample(source: .music, title: "Track", playing: false, identifier: "A")
        let playing = sample(source: .music, title: "Track", playing: true, identifier: "A")
        let target = ScriptablePlayerTarget(source: .music, processIdentifier: 123)
        let requests = AsyncStream<Void>.makeStream()
        let reader = HeldMusicReader(snapshot: paused, heldReadStarted: requests.continuation)
        let sender = PlaybackCommandSender(target: target, reader: reader, playing: playing)
        let preferenceDomain = "cascade.now-playing-tests.\(UUID().uuidString)"
        guard let preferences = UserDefaults(suiteName: preferenceDomain) else {
            throw CheckFailure.failed("Could not create isolated test preferences")
        }
        defer { preferences.removePersistentDomain(forName: preferenceDomain) }
        let provider = SystemNowPlayingProvider(
            reader        : reader,
            commandSender : sender,
            preferences   : preferences,
            resolveTargets: { [.music: target] }
        )
        var snapshots = provider.start().makeAsyncIterator()
        defer { provider.stop() }
        _ = await snapshots.next()
        let initial = await snapshots.next()
        try expect(initial == .some(paused), "The provider must publish the initial paused track")

        // Access reconciliation triggers the same refresh path as a player
        // notification, without broadcasting fake notifications to other apps.
        await provider.requestAccess()
        var heldReads = requests.stream.makeAsyncIterator()
        _ = await heldReads.next()
        try await provider.send(.togglePlayback, matching: paused)
        let readIsPending = await reader.hasHeldRead
        try expect(readIsPending, "Play must finish while the metadata reply is still held")
        await reader.releaseRead()
        let updated = await snapshots.next()
        try expect(updated == .some(playing), "The pre-command reply must not overwrite confirmed playback")

        await sender.denyNextCommand()
        do {
            try await provider.send(.togglePlayback, matching: playing)
            throw CheckFailure.failed("Command failures must reach the widget's retry feedback")
        } catch ScriptableMusicError.permissionRequired(.music) {}
        provider.stop()
        do {
            try await provider.send(.togglePlayback, matching: playing)
            throw CheckFailure.failed("A stopped provider must reject playback commands")
        } catch ScriptableMusicError.trackChanged {}
    }

    /// Music may acknowledge Previous before its scripting state has settled.
    /// No second notification is assumed: the provider must confirm the command.
    private static func checkPreviousTrackSettles() async throws {
        func track(_ id: String, playing: Bool) -> NowPlayingSnapshot {
            NowPlayingSnapshot(
                sourceBundleIdentifier: "com.apple.Music", title: id, artist: "Artist",
                isPlaying: playing, duration: 180, elapsed: 0, timestamp: .now,
                capabilities: [.togglePlayback, .previousTrack], trackIdentifier: id
            )
        }
        let original = track("A", playing: true)
        let previous = track("B", playing: true)
        let transitions: [(String, Result<NowPlayingSnapshot?, ScriptableMusicError>)] = [
            ("paused new track", .success(track("B", playing: false))),
            ("changing identity", .failure(.trackChanged)),
            ("temporarily stopped", .success(nil)),
            ("old track", .success(original))
        ]
        for (name, transition) in transitions {
            let target = ScriptablePlayerTarget(source: .music, processIdentifier: 456)
            let reader = TransitionMusicReader(
                target: target, original: original, transition: transition, settled: previous
            )
            let provider = SystemNowPlayingProvider(
                reader: reader, commandSender: reader, resolveTargets: { [.music: target] }
            )
            let received = SnapshotRecorder()
            let stream = provider.start()
            let observation = Task {
                for await snapshot in stream { received.latest = snapshot }
            }
            defer { provider.stop(); observation.cancel() }
            try await waitUntil("Initial playback must be available") { received.latest == original }
            try await provider.send(.previousTrack, matching: original)
            try await waitUntil("Previous must recover from \(name) without another player event") {
                received.latest == previous
            }
            // After settling, reads must stop instead of becoming permanent polling.
            try await Task.sleep(for: .milliseconds(1_100))
            let settledReadCount = await reader.readCount
            try await Task.sleep(for: .milliseconds(350))
            let laterReadCount = await reader.readCount
            try expect(laterReadCount == settledReadCount, "A completed transition must become idle")
        }

        let target = ScriptablePlayerTarget(source: .music, processIdentifier: 457)
        let reader = TransitionMusicReader(
            target: target, original: original, transition: .success(original), settled: previous
        )
        let provider = SystemNowPlayingProvider(
            reader: reader, commandSender: reader, resolveTargets: { [.music: target] }
        )
        var snapshots = provider.start().makeAsyncIterator()
        _ = await snapshots.next()
        _ = await snapshots.next()
        try await provider.send(.previousTrack, matching: original)
        provider.stop()
        try await Task.sleep(for: .milliseconds(100))
        let stoppedReadCount = await reader.readCount
        try await Task.sleep(for: .milliseconds(1_100))
        let finalReadCount = await reader.readCount
        try expect(finalReadCount == stoppedReadCount, "Stopping must cancel pending transition reads")
        try expect(provider.status == .stopped, "A late transition must not revive a stopped provider")
    }

    private static func checkPreviousTrackSettlesAfterSlowRead() async throws {
        let original = NowPlayingSnapshot(
            sourceBundleIdentifier: "com.apple.Music", title: "A", artist: "Artist",
            isPlaying: true, duration: 180, elapsed: 20, timestamp: .now,
            capabilities: [.togglePlayback, .previousTrack], trackIdentifier: "A"
        )
        let paused = sample(source: .music, title: "B", playing: false, identifier: "B")
        let playing = sample(source: .music, title: "B", playing: true, identifier: "B")
        let target = ScriptablePlayerTarget(source: .music, processIdentifier: 458)
        let reader = TransitionMusicReader(
            target: target, original: original, transition: .success(paused), settled: playing
        )
        let provider = SystemNowPlayingProvider(
            reader: reader, commandSender: reader, resolveTargets: { [.music: target] }
        )
        let received = SnapshotRecorder()
        let stream = provider.start()
        let observation = Task {
            for await snapshot in stream { received.latest = snapshot }
        }
        defer { provider.stop(); observation.cancel() }
        try await waitUntil("Initial playback must be available") { received.latest == original }
        let heldReadStarted = await reader.holdNextRead()
        await provider.requestAccess()
        var started = heldReadStarted.makeAsyncIterator()
        _ = await started.next()
        try await provider.send(.previousTrack, matching: original)
        // Both old wall-clock confirmation deadlines pass while the read is held.
        try await Task.sleep(for: .milliseconds(1_200))
        await reader.releaseRead()
        try await waitUntil("A slow pre-command read must not consume every playback confirmation") {
            received.latest == playing
        }
    }

    private static func checkPlayerInfoParsing() throws {
        try expect(ScriptablePlaybackState(playerInfo: ["Player State": "Paused"]) == .paused, "Music and Spotify announce a pause")
        try expect(ScriptablePlaybackState(playerInfo: ["Player State": "Playing"]) == .playing, "They announce playback")
        try expect(ScriptablePlaybackState(playerInfo: ["Player State": "Stopped"]) == .stopped, "They announce a stop")
        try expect(ScriptablePlaybackState(playerInfo: ["Name": "Song"]) == nil, "A notification without a state changes nothing")
        try expect(ScriptablePlaybackState(playerInfo: nil) == nil, "Nor does one without a payload")
    }

    /// Music answers "playing" for a while after the spacebar paused it. The
    /// announced pause must publish at once and survive the confirmation reads.
    private static func checkAnnouncedPauseOutranksStaleReads() async throws {
        let playing = sample(source: .music, title: "A", playing: true, identifier: "A")
        let target = ScriptablePlayerTarget(source: .music, processIdentifier: 459)
        let reader = TransitionMusicReader(target: target, original: playing, transition: .success(playing), settled: playing)
        let provider = SystemNowPlayingProvider(reader: reader, commandSender: reader, resolveTargets: { [.music: target] })
        let received = SnapshotRecorder()
        let stream = provider.start()
        let observation = Task { for await snapshot in stream { received.latest = snapshot } }
        defer { provider.stop(); observation.cancel() }
        try await waitUntil("Initial playback must be available") { received.latest == playing }
        let readsBefore = await reader.readCount

        provider.receivePlayerNotification(.paused, from: .music)
        try await Task.sleep(for: .milliseconds(20))
        try expect(received.latest?.isPlaying == false, "An announced pause must publish before any read")
        try expect(received.latest?.trackIdentifier == "A", "It keeps the track it paused")
        try await Task.sleep(for: .milliseconds(1_100))
        let readsAfter = await reader.readCount
        try expect(readsAfter > readsBefore, "The notification still confirms with reads")
        try expect(received.latest?.isPlaying == false, "Stale 'playing' replies inside the settle window must not reopen the notch")
    }

    private static func checkQuittingRepeatsTheEmptySelection() async throws {
        let playing = sample(source: .music, title: "A", playing: true, identifier: "A")
        let target = ScriptablePlayerTarget(source: .music, processIdentifier: 460)
        let reader = TransitionMusicReader(target: target, original: playing, transition: .success(playing), settled: playing)
        let running = RunningPlayers(targets: [.music: target])
        let provider = SystemNowPlayingProvider(reader: reader, commandSender: reader, resolveTargets: { running.targets })
        let recorder = EmissionRecorder()
        let stream = provider.start()
        let observation = Task { for await snapshot in stream { recorder.values.append(snapshot) } }
        defer { provider.stop(); observation.cancel() }
        try await waitUntil("Initial playback must be available") { recorder.values.last == playing }

        provider.receivePlayerNotification(.stopped, from: .music)
        try await waitUntil("A stop empties the selection") { recorder.values.last == .some(nil) }
        let emptiesBeforeQuit = recorder.values.filter { $0 == nil }.count
        running.targets = [:]
        provider.receivePlayerNotification(nil, from: .music)
        try await waitUntil("Quitting repeats the empty selection") {
            recorder.values.filter { $0 == nil }.count > emptiesBeforeQuit
        }
    }

    private final class RunningPlayers {
        var targets: [ScriptableMusicSource: ScriptablePlayerTarget]
        init(targets: [ScriptableMusicSource: ScriptablePlayerTarget]) { self.targets = targets }
    }

    private final class EmissionRecorder {
        var values: [NowPlayingSnapshot?] = []
    }

    private final class SnapshotRecorder {
        var latest: NowPlayingSnapshot?
    }

    private static func waitUntil(_ message: String, condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while !condition() {
            guard ContinuousClock.now < deadline else { throw CheckFailure.failed(message) }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private actor TransitionMusicReader: ScriptableMusicReading {
        let target: ScriptablePlayerTarget
        let original: NowPlayingSnapshot
        let transition: Result<NowPlayingSnapshot?, ScriptableMusicError>
        let settled: NowPlayingSnapshot
        private var hasCommand = false
        private var hasReadTransition = false
        private(set) var readCount = 0
        private var heldReadSignal: AsyncStream<Void>.Continuation?
        private var heldRead: CheckedContinuation<NowPlayingSnapshot?, Never>?

        init(target: ScriptablePlayerTarget, original: NowPlayingSnapshot,
             transition: Result<NowPlayingSnapshot?, ScriptableMusicError>, settled: NowPlayingSnapshot) {
            self.target = target
            self.original = original
            self.transition = transition
            self.settled = settled
        }

        func holdNextRead() -> AsyncStream<Void> {
            let pair = AsyncStream<Void>.makeStream()
            heldReadSignal = pair.continuation
            return pair.stream
        }

        func releaseRead() {
            heldRead?.resume(returning: original)
            heldRead = nil
        }

        func read(_ target: ScriptablePlayerTarget) async throws -> NowPlayingSnapshot? {
            guard target == self.target else { throw ScriptableMusicError.trackChanged }
            readCount += 1
            if let signal = heldReadSignal {
                heldReadSignal = nil
                return await withCheckedContinuation { continuation in
                    heldRead = continuation
                    signal.yield(())
                    signal.finish()
                }
            }
            guard hasCommand else { return original }
            guard !hasReadTransition else { return settled }
            hasReadTransition = true
            return try transition.get()
        }

        func send(_ command: MediaCommand, to target: ScriptablePlayerTarget, expectedTrack: String?) throws {
            guard case .previousTrack = command, target == self.target,
                  expectedTrack == original.trackIdentifier else { throw ScriptableMusicError.trackChanged }
            hasCommand = true
        }

        func requestAccess(_ target: ScriptablePlayerTarget) {}
        func reset() { releaseRead() }
        func discardArtwork(_ source: ScriptableMusicSource) {}
    }

    private actor HeldMusicReader: ScriptableMusicReading {
        private var snapshot: NowPlayingSnapshot
        private let heldReadStarted: AsyncStream<Void>.Continuation
        private var heldRead: CheckedContinuation<NowPlayingSnapshot?, Never>?
        private var readCount = 0
        var hasHeldRead: Bool { heldRead != nil }

        init(snapshot: NowPlayingSnapshot, heldReadStarted: AsyncStream<Void>.Continuation) {
            self.snapshot = snapshot
            self.heldReadStarted = heldReadStarted
        }

        func read(_ target: ScriptablePlayerTarget) async throws -> NowPlayingSnapshot? {
            readCount += 1
            if readCount == 2 {
                return await withCheckedContinuation { continuation in
                    heldRead = continuation
                    heldReadStarted.yield(())
                }
            }
            return snapshot
        }

        func update(_ snapshot: NowPlayingSnapshot) { self.snapshot = snapshot }
        func releaseRead() {
            // Return the paused snapshot captured before the command.
            heldRead?.resume(returning: NowPlayingBehaviorChecks.sample(source: .music, title: "Track", playing: false, identifier: "A"))
            heldRead = nil
        }
        func requestAccess(_ target: ScriptablePlayerTarget) {}
        func reset() { heldRead?.resume(returning: nil); heldRead = nil }
        func discardArtwork(_ source: ScriptableMusicSource) {}
        func send(_ command: MediaCommand, to target: ScriptablePlayerTarget, expectedTrack: String?) throws {
            throw ScriptableMusicError.unavailable("Playback was routed through the busy metadata reader")
        }
    }

    private actor PlaybackCommandSender: ScriptableMusicCommandSending {
        let target : ScriptablePlayerTarget
        let reader : HeldMusicReader
        let playing: NowPlayingSnapshot
        private var shouldDeny = false

        init(target: ScriptablePlayerTarget, reader: HeldMusicReader, playing: NowPlayingSnapshot) {
            self.target = target
            self.reader = reader
            self.playing = playing
        }
        func denyNextCommand() { shouldDeny = true }
        func send(_ command: MediaCommand, to target: ScriptablePlayerTarget, expectedTrack: String?) async throws {
            guard case .togglePlayback = command, target == self.target, expectedTrack == "A" else {
                throw ScriptableMusicError.trackChanged
            }
            if shouldDeny { throw ScriptableMusicError.permissionRequired(.music) }
            await reader.update(playing)
        }
    }

    /// probeAuthorizedPlayers is opt-in and read-only. It cannot launch a
    /// player, request Automation permission, or send any playback command.
    private static func probeAuthorizedPlayers() async {
        let reader = ScriptableMusicAppleEventReader()
        for source in ScriptableMusicSource.allCases {
            guard let application = NSRunningApplication.runningApplications(withBundleIdentifier: source.bundleIdentifier)
                .first(where: { !$0.isTerminated && $0.isFinishedLaunching })
            else {
                print("\(source.displayName): not running")
                continue
            }
            let target = ScriptablePlayerTarget(source: source, processIdentifier: application.processIdentifier)
            do {
                if let snapshot = try await reader.read(target) {
                    print("\(source.displayName): \(snapshot.title) — \(snapshot.artist); playing=\(snapshot.isPlaying), artwork=\(snapshot.artworkData?.count ?? 0) bytes")
                } else {
                    print("\(source.displayName): no active track")
                }
            } catch {
                print("\(source.displayName): \(error.localizedDescription)")
            }
        }
        await reader.reset()
    }

    nonisolated private static func sample(source: ScriptableMusicSource, title: String, playing: Bool, identifier: String? = nil) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
            sourceBundleIdentifier: source.bundleIdentifier,
            title                 : title,
            artist                : "Artist",
            isPlaying             : playing,
            duration              : 100,
            elapsed               : 1,
            timestamp             : Date(timeIntervalSince1970: 1_000),
            capabilities          : [.togglePlayback],
            trackIdentifier       : identifier
        )
    }

    private enum CheckFailure: Error { case failed(String) }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure.failed(message) }
    }
}
#endif
