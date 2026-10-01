//
//  PluginResourceProfile.swift
//  CascadeKit
//

/// PluginResourceProfile is how a plugin uses resources. v1 has one profile: plugins wake only
/// for a source event, a scheduled deadline or a user action, and never poll.
public enum PluginResourceProfile: String, Codable, Sendable {

    case eventDriven
}
