//
//  PluginContext.swift
//  CascadeKit
//

import CascadeContracts

/// PluginContext is what the host passes with every event. For now it names the plugin; the
/// service clients join it with the first service.
public struct PluginContext: Sendable {

    public let plugin: PluginID

    public init(plugin: PluginID) {
        self.plugin = plugin
    }
}
