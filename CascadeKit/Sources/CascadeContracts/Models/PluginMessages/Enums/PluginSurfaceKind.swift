//
//  PluginSurfaceKind.swift
//  CascadeKit
//

/// PluginSurfaceKind names the three places a feature's content can appear. A publication
/// targets exactly one of them, and the kernel accepts it only where the feature declared it.
public enum PluginSurfaceKind: String, Codable, Hashable, Sendable {

    case widget
    case activity
    case notice
}
