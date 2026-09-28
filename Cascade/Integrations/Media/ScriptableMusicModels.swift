//
//  ScriptableMusicModels.swift
//  Cascade
//

import CascadeKit
import Foundation

/// ScriptableMusicSource lists players with a native scripting dictionary and
/// real playback change notifications. The adapter never claims global access.
nonisolated enum ScriptableMusicSource: String, CaseIterable, Sendable {
    case music
    case spotify

    var bundleIdentifier: String {
        switch self {
        case .music: "com.apple.Music"
        case .spotify: "com.spotify.client"
        }
    }

    var displayName: String {
        switch self {
        case .music: "Musica"
        case .spotify: "Spotify"
        }
    }

    var notificationName: Notification.Name {
        switch self {
        case .music: Notification.Name("com.apple.Music.playerInfo")
        case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }
}

/// ScriptablePlayerTarget addresses an already running process. PID addressing
/// makes it impossible for a metadata query to launch an absent player.
nonisolated struct ScriptablePlayerTarget: Equatable, Sendable {
    let source           : ScriptableMusicSource
    let processIdentifier: Int32
}

/// ScriptablePlaybackState separates a stopped session from a paused track.
nonisolated enum ScriptablePlaybackState: Sendable {
    case stopped
    case paused
    case playing
    case scrubbing

    /// init(playerInfo:) reads the state both players put in their playback
    /// notification, the same key and values for Music and Spotify.
    init?(playerInfo: [AnyHashable: Any]?) {
        switch playerInfo?["Player State"] as? String {
        case "Playing": self = .playing
        case "Paused" : self = .paused
        case "Stopped": self = .stopped
        default       : return nil
        }
    }
}

extension NowPlayingSnapshot {
    /// announcing(isPlaying:at:) is this track with the playback a player has
    /// just announced, its position frozen or resumed at `date`.
    nonisolated func announcing(
        isPlaying: Bool,
        at date  : Date
    ) -> NowPlayingSnapshot {
        guard isPlaying != self.isPlaying else { return self }
        return NowPlayingSnapshot(
            sourceBundleIdentifier: sourceBundleIdentifier,
            title                 : title,
            artist                : artist,
            isPlaying             : isPlaying,
            duration              : duration,
            elapsed               : position(at: date),
            timestamp             : date,
            capabilities          : capabilities,
            artworkData           : artworkData,
            trackIdentifier       : trackIdentifier,
            isFavorite            : isFavorite,
            playbackRate          : playbackRate
        )
    }
}

/// NowPlayingAnnouncement is the playback a player's own notification carried.
/// Music posts it before its scripting state settles: for about a second a
/// read can still answer "playing" after a pause, and the confirmation reads
/// then left the notch open until the next event. Within that window the
/// announcement decides playback; reads still supply everything else.
nonisolated struct NowPlayingAnnouncement: Sendable {
    static let settleWindow = Duration.milliseconds(1_500)

    let state: ScriptablePlaybackState
    let time : ContinuousClock.Instant

    /// applied(to:startedAt:) corrects a read begun inside the window.
    func applied(
        to snapshot: NowPlayingSnapshot?,
        startedAt  : ContinuousClock.Instant
    ) -> NowPlayingSnapshot? {
        guard startedAt < time.advanced(by: Self.settleWindow) else { return snapshot }
        guard state != .stopped else { return nil }
        return snapshot?.announcing(isPlaying: state == .playing || state == .scrubbing, at: .now)
    }
}

/// ScriptableTrackMetadata normalizes each player's documented scripting units
/// and exposes only commands whose prerequisites are available in real data.
nonisolated struct ScriptableTrackMetadata: Sendable {
    let identifier: String?
    let title     : String
    let artist    : String
    let duration  : Double?
    let favorite  : Bool?

    var identity: String {
        identifier ?? title + "\u{1f}" + artist
    }

    func snapshot(
        source     : ScriptableMusicSource,
        state      : ScriptablePlaybackState,
        elapsed    : TimeInterval,
        timestamp  : Date,
        artworkData: Data?
    ) -> NowPlayingSnapshot? {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard state != .stopped, !normalizedTitle.isEmpty else { return nil }
        let seconds = duration.map { source == .spotify ? $0 / 1_000 : $0 }
        let knownDuration = seconds.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        let favoriteState = source == .music ? favorite : nil
        var capabilities: MediaCommandCapabilities = [.togglePlayback, .previousTrack, .nextTrack]
        if knownDuration != nil { capabilities.insert(.seek) }
        if favoriteState != nil { capabilities.insert(.favorite) }
        return NowPlayingSnapshot(
            sourceBundleIdentifier: source.bundleIdentifier,
            title                 : normalizedTitle,
            artist                : artist.trimmingCharacters(in: .whitespacesAndNewlines),
            isPlaying             : state == .playing || state == .scrubbing,
            duration              : knownDuration,
            elapsed               : elapsed,
            timestamp             : timestamp,
            capabilities          : capabilities,
            artworkData           : artworkData,
            trackIdentifier       : identity,
            isFavorite            : favoriteState,
            playbackRate          : state == .scrubbing ? 0 : 1
        )
    }
}

/// NowPlayingSourceSelection prefers audible playback, then the most recently
/// updated player. Removing a source also removes all of its retained artwork.
nonisolated struct NowPlayingSourceSelection {
    private var snapshots: [ScriptableMusicSource: NowPlayingSnapshot] = [:]
    private var recency  : [ScriptableMusicSource] = []

    var current: NowPlayingSnapshot? {
        let ordered = recency.compactMap { snapshots[$0] }
        return ordered.first(where: \.isPlaying) ?? ordered.first
    }

    /// matches validates the track represented by a captured UI action. A
    /// stable identifier takes precedence over visible metadata, since distinct
    /// tracks may have the same title. Metadata is the fallback only when both
    /// snapshots lack an identifier; changed identity availability is rejected.
    func matches(_ expected: NowPlayingSnapshot) -> Bool {
        guard let current,
              current.sourceBundleIdentifier == expected.sourceBundleIdentifier
        else { return false }
        if current.trackIdentifier != nil || expected.trackIdentifier != nil {
            return current.trackIdentifier == expected.trackIdentifier
        }
        return current.title == expected.title && current.artist == expected.artist
    }

    /// announce applies a player's own notification to the track it holds.
    mutating func announce(
        _ announcement: NowPlayingAnnouncement,
        from source   : ScriptableMusicSource
    ) {
        guard let held = snapshots[source] else { return }
        receive(
            announcement.applied(to: held, startedAt: announcement.time),
            from: source
        )
    }

    mutating func receive(
        _ snapshot: NowPlayingSnapshot?,
        from source: ScriptableMusicSource
    ) {
        snapshots[source] = snapshot
        recency.removeAll { $0 == source }
        if snapshot != nil { recency.insert(source, at: 0) }
    }
}

/// NowPlayingRefreshRevisions invalidates stale asynchronous work without
/// retaining tasks or player objects. Sequence numbers survive a reset so an
/// old process can never match a later process that uses the same source.
nonisolated struct NowPlayingRefreshRevisions {
    private var counter: UInt64 = 0
    private var latest : [ScriptableMusicSource: UInt64] = [:]

    mutating func request(_ source: ScriptableMusicSource) -> UInt64 {
        counter &+= 1
        latest[source] = counter
        return counter
    }

    func current(_ source: ScriptableMusicSource) -> UInt64? { latest[source] }

    func accepts(
        _ revision: UInt64,
        for source: ScriptableMusicSource
    ) -> Bool {
        latest[source] == revision
    }

    mutating func remove(_ source: ScriptableMusicSource) { latest[source] = nil }
    mutating func reset() { latest.removeAll() }
}

/// ScriptableMusicError carries actionable failures across the worker boundary.
nonisolated enum ScriptableMusicError: LocalizedError, Sendable, Equatable {
    case permissionRequired(ScriptableMusicSource)
    case unavailable(String)
    case trackChanged

    var errorDescription: String? {
        switch self {
        case .permissionRequired(let source):
            "Consenti a Cascade di controllare \(source.displayName) in Impostazioni di Sistema → Privacy e sicurezza → Automazione."
        case .unavailable(let reason): reason
        case .trackChanged: "Il brano è cambiato. Riprova sul brano attuale."
        }
    }
}

/// ScriptableMusicCommandSending lets playback use a worker independent of
/// metadata and artwork, so a slow read cannot hold a user's command in line.
nonisolated protocol ScriptableMusicCommandSending: Sendable {
    func send(
        _ command: MediaCommand,
        to target: ScriptablePlayerTarget,
        expectedTrack: String?
    ) async throws
}

/// ScriptableMusicReading isolates AppleEvents and artwork from UI ownership.
nonisolated protocol ScriptableMusicReading: ScriptableMusicCommandSending {
    func read(_ target: ScriptablePlayerTarget) async throws -> NowPlayingSnapshot?
    func requestAccess(_ target: ScriptablePlayerTarget) async throws
    func reset() async
    func discardArtwork(_ source: ScriptableMusicSource) async
}
