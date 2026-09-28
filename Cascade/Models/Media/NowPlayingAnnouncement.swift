//
//  NowPlayingAnnouncement.swift
//  Cascade
//

import CascadeKit
import Foundation

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
