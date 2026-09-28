//
//  ScriptablePlaybackState.swift
//  Cascade
//

import CascadeKit
import Foundation

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
