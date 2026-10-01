//
//  PluginPublicationKey.swift
//  CascadeKit
//

import CascadeContracts

/// PluginPublicationKey names one place a plugin's content lives: the plugin, the feature and
/// the surface. Surfaces report their visibility by it, and actions name it.
public struct PluginPublicationKey: Hashable, Sendable {

    public let plugin : PluginID
    public let feature: String
    public let surface: PluginSurfaceKind

    public init(
        plugin : PluginID,
        feature: String,
        surface: PluginSurfaceKind
    ) {
        self.plugin  = plugin
        self.feature = feature
        self.surface = surface
    }
}
