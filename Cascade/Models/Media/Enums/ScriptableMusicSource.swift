//
//  ScriptableMusicSource.swift
//  Cascade
//

import Foundation

/// ScriptableMusicSource lists players with a native scripting dictionary and
/// real playback change notifications. The adapter never claims global access.
nonisolated enum ScriptableMusicSource: String, CaseIterable, Sendable {

    case music
    case spotify

    var bundleIdentifier: String {
        switch self {
            case .music  : "com.apple.Music"
            case .spotify: "com.spotify.client"
        }
    }

    var displayName: String {
        switch self {
            case .music  : String(localized: "Music")
            case .spotify: "Spotify"
        }
    }

    var notificationName: Notification.Name {
        switch self {
            case .music  : Notification.Name("com.apple.Music.playerInfo")
            case .spotify: Notification.Name("com.spotify.client.PlaybackStateChanged")
        }
    }
}
