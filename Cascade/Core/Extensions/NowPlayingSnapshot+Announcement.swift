//
//  NowPlayingSnapshot+Announcement.swift
//  Cascade
//

import CascadeKit
import Foundation

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
