//
//  PluginExecutor.swift
//  CascadeKit
//

import CascadeContracts

/// PluginExecutor runs plugin code where the kernel does not: on a thread of its own in process,
/// in the shared PluginHost, or later in a process per plugin. The kernel only starts,
/// dispatches and stops; how a stop is enforced is the executor's business. Every method must
/// return at once, because the engine calls them from its own queue.
public protocol PluginExecutor: Sendable {

    /// observe registers the engine's handler for the host's availability. The executor reports
    /// its current availability at once, then every change, from any thread.
    func observe(_ handler: @escaping @Sendable (PluginExecutorEvent) -> Void)

    /// start loads the plugin behind `entryPoint`.
    func start(
        _ plugin  : PluginID,
        entryPoint: String
    )

    /// dispatch delivers one event. `completion` runs once, on any thread, unless the plugin
    /// never returns.
    func dispatch(
        _ event   : PluginEvent,
        to plugin : PluginID,
        completion: @escaping @Sendable (PluginExecutionResult) -> Void
    )

    /// stop abandons whatever the plugin is doing. The kernel calls it on a hang.
    func stop(_ plugin: PluginID)
}
