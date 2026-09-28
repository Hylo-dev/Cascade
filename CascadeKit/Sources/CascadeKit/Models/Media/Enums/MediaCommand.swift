//
//  MediaCommand.swift
//  CascadeKit
//

/// MediaCommand carries intent without leaking a player's transport into UI.
public nonisolated enum MediaCommand: Sendable {

    case togglePlayback
    case previousTrack
    case nextTrack
    case seek(Double)
    case toggleFavorite
}
