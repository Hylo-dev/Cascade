//
//  BatteryPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Synchronization

/// BatteryPlugin is the battery widget: the kernel-drawn battery, the charge and what the Mac is
/// doing with it. It reads the `power` source and publishes only when the state changes, so a
/// source that repeats itself costs one comparison; a refresh, which comes at start and after a
/// restart, gets the last state again. It never asks for a wake. A Mac without a built-in
/// battery has no power state, so the widget never appears there. The last state is its only
/// memory; PluginHost runs it on one thread, so the lock is never contended.
final class BatteryPlugin: PluginProvider {

    static let id      = PluginID(rawValue: "com.cascade.battery")!
    static let feature = "battery"

    private let last = Mutex<PluginPowerState?>(nil)

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        switch event {
            case .source(let source):
                guard let state = PluginPowerState(source) else { return try PluginOutput() }

                let changed = last.withLock { last in
                    defer { last = state }
                    return last != state
                }
                guard changed else { return try PluginOutput() }

                return try PluginOutput(publications: [BatteryFace.publication(for: state)])

            case .refresh:
                guard let state = last.withLock({ $0 }) else { return try PluginOutput() }

                return try PluginOutput(publications: [BatteryFace.publication(for: state)])

            default:
                return try PluginOutput()
        }
    }
}
