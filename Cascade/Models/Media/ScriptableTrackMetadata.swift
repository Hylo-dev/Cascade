//
//  ScriptableTrackMetadata.swift
//  Cascade
//

import CascadeKit
import Foundation

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

        let seconds       = duration.map { rawDuration in source == .spotify ? rawDuration / 1_000 : rawDuration }
        let knownDuration = seconds.flatMap { candidate in candidate.isFinite && candidate > 0 ? candidate : nil }
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
