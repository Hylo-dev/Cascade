//
//  BluetoothPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Synchronization

/// BluetoothPlugin is Cascade's Bluetooth notice as a plugin. It reads the `bluetooth` source: a
/// device that connects, disconnects or brings its audio back shows the notice, and a battery or
/// model reading of that event only updates it. Cascade's menu previews it through the `preview`
/// action, which shows a sample, AirPods Pro, and leaves the baseline alone. Its reducer is its
/// only state; PluginHost runs it on one thread, so the lock is never contended.
public final class BluetoothPlugin: PluginProvider {

    public static let id      = PluginID(rawValue: "com.cascade.bluetooth")!
    public static let feature = "connection"
    public static let preview = "preview"

    private let reducer = Mutex(BluetoothNoticeReducer())

    public init() {}

    public func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        switch event {
            case .source(let source):
                guard let state = PluginBluetoothState(source), let delivery = reducer.withLock({ $0.receive(state) }) else { return try PluginOutput() }

                return try PluginOutput(publications: [BluetoothNotice.publication(for: state, delivery: delivery)])

            case .action(let action) where action.action == Self.preview:
                reducer.withLock { $0.previewShown() }

                return try PluginOutput(publications: [BluetoothNotice.publication(for: BluetoothNotice.sample(), delivery: .show)])

            default:
                return try PluginOutput()
        }
    }
}
