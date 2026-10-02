//
//  InProcessExecutor.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginHost
import CascadePluginSDK

/// InProcessExecutor runs plugins inside Cascade, for tests and development only, with the same
/// runner PluginHost uses. Stopping a plugin abandons its thread's work: a hung `handle()` keeps
/// its thread, at most one per plugin, and a plugin restarted while still stuck waits behind it,
/// hangs again and is quarantined.
public final class InProcessExecutor: PluginExecutor {

    private let runner: PluginRunner

    public init(providers: [String: any PluginProvider]) {
        runner = PluginRunner(providers: providers)
    }

    /// observe reports the double as always available: its host is Cascade itself.
    public func observe(_ handler: @escaping @Sendable (PluginExecutorEvent) -> Void) {
        handler(.available)
    }

    /// restart does nothing: plugins run in this process, which is never given up on.
    public func restart() {}

    public func start(
        _ plugin  : PluginID,
        entryPoint: String
    ) {
        runner.start(plugin, entryPoint: entryPoint)
    }

    public func dispatch(
        _ event   : PluginEvent,
        to plugin : PluginID,
        completion: @escaping @Sendable (PluginExecutionResult) -> Void
    ) {
        runner.run(event, for: plugin) { run in
            completion(PluginExecutionResult(output: run.output, cpuTime: run.cpuTime))
        }
    }

    public func stop(_ plugin: PluginID) {
        runner.abandon(plugin)
    }
}
