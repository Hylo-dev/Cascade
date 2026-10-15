//
//  DevicesPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Synchronization

/// DevicesPlugin is the devices widget: the Bluetooth devices connected now, each with its
/// symbol, name and charge. It reads the `bluetooth` source, whose every state lists them, the
/// baseline included, so a widget added long after the devices connected still knows them. A
/// state is also about the device of its latest event, which the widget does not show, so the
/// plugin keeps the list and whether Bluetooth works, as a baseline, and publishes only when
/// that changes; a refresh, which comes at start and after a restart, gets it again. It never
/// asks for a wake. PluginHost runs it on one thread, so the lock is never contended.
final class DevicesPlugin: PluginProvider {

    static let id      = PluginID(rawValue: "com.cascade.devices")!
    static let feature = "devices"

    private let last = Mutex<PluginBluetoothState?>(nil)

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        switch event {
            case .source(let source):
                guard let state = PluginBluetoothState(source) else { return try PluginOutput() }

                let shown   = PluginBluetoothState.baseline(isAvailable: state.isAvailable, connectedDevices: state.connectedDevices)
                let changed = last.withLock { last in
                    defer { last = shown }
                    return last != shown
                }
                guard changed else { return try PluginOutput() }

                return try PluginOutput(publications: [DevicesFace.publication(for: shown)])

            case .refresh:
                guard let shown = last.withLock({ $0 }) else { return try PluginOutput() }

                return try PluginOutput(publications: [DevicesFace.publication(for: shown)])

            default:
                return try PluginOutput()
        }
    }
}
