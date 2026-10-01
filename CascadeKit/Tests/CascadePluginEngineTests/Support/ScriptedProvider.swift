//
//  ScriptedProvider.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK

/// ScriptedProvider is a plugin whose answer is the closure the test gives it.
struct ScriptedProvider: PluginProvider {

    let script: @Sendable (PluginEvent) throws -> PluginOutput

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        try script(event)
    }
}
