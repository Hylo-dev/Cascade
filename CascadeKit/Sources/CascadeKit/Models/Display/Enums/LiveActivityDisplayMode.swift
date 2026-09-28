//
//  LiveActivityDisplayMode.swift
//  CascadeKit
//

/// LiveActivityDisplayMode describes which connected displays receive compact
/// copies of shared Live Activities.
public nonisolated enum LiveActivityDisplayMode: Codable, Equatable, Sendable {

    case allDisplays
    case focusedDisplay
    case fixedDisplay(DisplayIdentity)
}
