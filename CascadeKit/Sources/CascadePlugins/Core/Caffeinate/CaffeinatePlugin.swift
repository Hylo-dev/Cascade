//
//  CaffeinatePlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK

/// CaffeinatePlugin is a placeholder for the keep-awake widget while the redesign lands: it
/// stays registered under its id and feature so the manifest, the widget arrangement and the
/// registry keep resolving, but it answers every event with an empty output and publishes
/// nothing. The redesign's plugin task replaces it with the real face.
final class CaffeinatePlugin: PluginProvider {

    static let id      = PluginID(rawValue: "com.cascade.caffeinate")!
    static let feature = "awake"

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        try PluginOutput()
    }
}
