//
//  ChargingPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Synchronization

/// ChargingPlugin is Cascade's charging notice as a plugin. It reads the `power` source: a
/// connection shows the notice, a change while connected only updates it, and unplugging
/// withdraws it. Cascade's menu previews it through the `preview` action, which shows a sample
/// and leaves the baseline alone. Its reducer is its only state; PluginHost runs it on one
/// thread, so the lock is never contended.
public final class ChargingPlugin: PluginProvider {

    public static let id      = PluginID(rawValue: "com.cascade.power")!
    public static let feature = "charging"
    public static let preview = "preview"

    private let reducer = Mutex(PowerConnectionReducer())

    public init() {}

    public func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        switch event {
            case .source(let source):
                guard let state = PluginPowerState(source) else { return try PluginOutput() }

                switch reducer.withLock({ $0.receive(state) }) {
                    case .connected(let state)?:
                        return try PluginOutput(publications: [ChargingNotice.publication(for: state, delivery: .show)])

                    case .updated(let state)?:
                        return try PluginOutput(publications: [ChargingNotice.publication(for: state, delivery: .update)])

                    case .disconnected?:
                        return try PluginOutput(publications: [PluginPublication(feature: Self.feature, surface: .notice, document: nil)])

                    case nil:
                        return try PluginOutput()
                }

            case .action(let action) where action.action == Self.preview:
                let sample = PluginPowerState(percentage: 19, isExternalPower: true, isCharging: true, isLowPowerMode: action.value == .bool(true))

                return try PluginOutput(publications: [ChargingNotice.publication(for: sample, delivery: .show)])

            default:
                return try PluginOutput()
        }
    }
}
