//
//  PluginSurfaceKind.swift
//  CascadeKit
//

/// PluginSurfaceKind names the four places a feature's content can appear. A publication
/// targets exactly one of them, and the kernel accepts it only where the feature declared it.
/// `detail` is the full page a click on the feature's widget opens.
public enum PluginSurfaceKind: String, Codable, Hashable, Sendable {

    case widget
    case activity
    case notice
    case detail
}
