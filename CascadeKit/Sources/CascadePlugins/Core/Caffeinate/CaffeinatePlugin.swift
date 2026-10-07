//
//  CaffeinatePlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Synchronization

/// CaffeinatePlugin is the keep-awake widget and its fullscreen options page. The power
/// assertion itself stays in Cascade, which owns the native resource: this plugin only draws
/// the `caffeinate` source's state and declares the controls Cascade acts on once the broker
/// accepted them. It publishes only when the state changes and never asks for a wake, since a
/// timed session's end is a fixed date the kernel draws. The last state is its only memory, for
/// a refresh; PluginHost runs it on one thread, so the lock is never contended.
final class CaffeinatePlugin: PluginProvider {

    static let id      = PluginID(rawValue: "com.cascade.caffeinate")!
    static let feature = "awake"

    private let last = Mutex<PluginCaffeinateState?>(nil)

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        switch event {
            case .source(let source):
                guard let state = PluginCaffeinateState(source) else { return try PluginOutput() }

                let changed = last.withLock { last in
                    defer { last = state }
                    return last != state
                }
                guard changed else { return try PluginOutput() }

                return try PluginOutput(publications: [CaffeinateFace.publication(for: state)])

            case .refresh:
                guard let state = last.withLock({ $0 }) else { return try PluginOutput() }

                return try PluginOutput(publications: [CaffeinateFace.publication(for: state)])

            default:
                return try PluginOutput()
        }
    }
}

/// CaffeinateCommand is what an accepted Caffeinate control asks Cascade's native owner to do.
/// Every control asks for an absolute value, never a flip: the power switch says on or off, a
/// duration names its minutes, the display switch names its state. A late or repeated request
/// is therefore either already satisfied or applies to the session the user now sees, so no
/// freshness token has to travel in node identities, and a new publication updates controls in
/// place instead of replacing every one of them.
public enum CaffeinateCommand: Equatable, Sendable {

    case setActive(Bool)
    case setDuration(minutes: Int)
    case setKeepsDisplayAwake(Bool)

    public static let plugin    = CaffeinatePlugin.id
    public static let feature   = CaffeinatePlugin.feature
    public static let durations = [0, 15, 30, 60, 120, 240, 480]

    /// init(node:value:) decodes an accepted control from the identity the kernel gave its node
    /// and the value it carries. The caller has already checked the request is this widget's.
    public init?(
        node : String,
        value: PluginValue?
    ) {
        switch value {
            case .bool(let isOn)?:
                if CaffeinateFace.Node.power.contains(where: { node == CaffeinateFace.Node.reference($0, kind: "toggle") }) {
                    self = .setActive(isOn)
                } else if node == CaffeinateFace.Node.reference(CaffeinateFace.Node.display, kind: "toggle") {
                    self = .setKeepsDisplayAwake(isOn)
                } else {
                    return nil
                }

            case nil:
                guard let minutes = Self.durations.first(where: {
                    node == CaffeinateFace.Node.reference(CaffeinateFace.Node.duration($0), kind: "button")
                }) else { return nil }

                self = .setDuration(minutes: minutes)

            default:
                return nil
        }
    }
}
