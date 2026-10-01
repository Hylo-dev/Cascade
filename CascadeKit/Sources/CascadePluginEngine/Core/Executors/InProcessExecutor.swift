//
//  InProcessExecutor.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Synchronization

/// InProcessExecutor runs plugins inside Cascade, for tests and development only. Each plugin
/// gets one serial queue, so its `handle()` runs on one thread at a time and that thread's CPU
/// time is the plugin's. Stopping a plugin abandons the work on its queue: a hung `handle()`
/// keeps its thread, at most one per plugin, and what was queued behind it is skipped. A plugin
/// restarted while still stuck waits behind its own stuck thread, hangs again and is
/// quarantined, so a stuck plugin never takes a second thread.
public final class InProcessExecutor: PluginExecutor {

    private struct Slot: Sendable {

        let provider  : (any PluginProvider)?
        let queue     : DispatchQueue
        var generation: UInt64
    }

    private let providers: [String: any PluginProvider]
    private let slots    = Mutex<[PluginID: Slot]>([:])

    public init(providers: [String: any PluginProvider]) {
        self.providers = providers
    }

    /// observe reports the double as always available: its host is Cascade itself.
    public func observe(_ handler: @escaping @Sendable (PluginExecutorEvent) -> Void) {
        handler(.available)
    }

    public func start(
        _ plugin  : PluginID,
        entryPoint: String
    ) {
        slots.withLock { slots in
            if slots[plugin] != nil {
                slots[plugin]?.generation += 1
            } else {
                slots[plugin] = Slot(
                    provider  : providers[entryPoint],
                    queue     : DispatchQueue(label: "cascade.plugin." + plugin.rawValue, qos: .utility),
                    generation: 0
                )
            }
        }
    }

    public func dispatch(
        _ event   : PluginEvent,
        to plugin : PluginID,
        completion: @escaping @Sendable (PluginExecutionResult) -> Void
    ) {
        guard let slot = slots.withLock({ $0[plugin] }) else {
            completion(PluginExecutionResult(output: nil, cpuTime: .zero))
            return
        }

        slot.queue.async { [self] in
            guard slots.withLock({ $0[plugin]?.generation }) == slot.generation else { return }

            let context = PluginContext(plugin: plugin)
            let started = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            let output  = try? slot.provider?.handle(event, context: context)
            let spent   = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - started

            completion(PluginExecutionResult(output: output, cpuTime: .nanoseconds(Int64(spent))))
        }
    }

    public func stop(_ plugin: PluginID) {
        slots.withLock { slots in
            slots[plugin]?.generation += 1
        }
    }
}
