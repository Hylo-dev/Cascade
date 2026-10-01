//
//  PluginProvider.swift
//  CascadeKit
//

import CascadeContracts

/// PluginProvider is a plugin: a type that answers events with output. `handle` runs on the
/// plugin's own thread, inside Cascade for the development double and inside PluginHost in
/// production, and the same code serves both. It must return within the kernel's deadline,
/// 250 ms to start with; returning later counts as a hang, and the plugin is stopped. After any
/// restart a plugin receives the latest state of its sources and a refresh, which is all it
/// needs to rebuild what it shows.
public protocol PluginProvider: Sendable {

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput
}
