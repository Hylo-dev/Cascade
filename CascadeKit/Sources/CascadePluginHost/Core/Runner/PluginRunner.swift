//
//  PluginRunner.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Synchronization

/// PluginRunner runs plugins on threads of their own, wherever it lives: inside PluginHost in
/// production and inside Cascade for the development double, so a plugin runs the same code in
/// both. Each plugin gets one serial queue, so its `handle()` runs on one thread at a time and
/// that thread's CPU time is the plugin's. Abandoning a plugin skips what is queued behind its
/// current work: a hung `handle()` keeps its thread, at most one per plugin, and a plugin started
/// again while still stuck waits behind its own thread instead of taking a second one.
public final class PluginRunner: Sendable {

    /// Run is what one dispatch came to: the plugin's output, or none when `handle()` threw or no
    /// plugin answers to the entry point, and the CPU time its thread spent.
    public struct Run: Sendable {

        public let output : PluginOutput?
        public let cpuTime: Duration
    }

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

    public func run(
        _ event   : PluginEvent,
        for plugin: PluginID,
        completion: @escaping @Sendable (Run) -> Void
    ) {
        guard let slot = slots.withLock({ $0[plugin] }) else {
            completion(Run(output: nil, cpuTime: .zero))
            return
        }

        slot.queue.async { [self] in
            guard slots.withLock({ $0[plugin]?.generation }) == slot.generation else { return }

            let context = PluginContext(plugin: plugin)
            let started = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            let output  = try? slot.provider?.handle(event, context: context)
            let spent   = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID) - started

            completion(Run(output: output, cpuTime: .nanoseconds(Int64(spent))))
        }
    }

    public func abandon(_ plugin: PluginID) {
        slots.withLock { slots in
            slots[plugin]?.generation += 1
        }
    }
}
