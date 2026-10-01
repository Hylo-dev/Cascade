//
//  PluginEvent.swift
//  CascadeKit
//

import Foundation

/// PluginEvent is everything that can wake a plugin: a `refresh` asking for its current
/// content (at start, after a restart, or when a visible surface went stale), the latest state
/// of a source it declared, the `wake` it asked for in its last output, or a user action on one
/// of its controls. Nothing else runs plugin code, so a plugin with no sources and no wake
/// costs nothing once it has published.
public enum PluginEvent: Codable, Equatable, Sendable {

    case refresh
    case source(PluginSourceEvent)
    case wake
    case action(PluginActionEvent)
}
