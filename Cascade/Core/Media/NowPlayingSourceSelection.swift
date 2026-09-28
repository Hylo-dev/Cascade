//
//  NowPlayingSourceSelection.swift
//  Cascade
//

import CascadeKit
import Foundation

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
        _ snapshot : NowPlayingSnapshot?,
        from source: ScriptableMusicSource
    ) {
        snapshots[source] = snapshot
        recency.removeAll { $0 == source }
        if snapshot != nil { recency.insert(source, at: 0) }
    }
}
