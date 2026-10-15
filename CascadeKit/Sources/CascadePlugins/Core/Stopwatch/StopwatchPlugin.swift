//
//  StopwatchPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Synchronization

/// StopwatchPlugin is the stopwatch widget: start, pause, resume and reset. The kernel draws the
/// running count, so the plugin runs only when a button is pressed, and it never asks for a wake.
/// A refresh publishes the current face; a press that changes nothing publishes nothing. The
/// state lives here behind a lock, so a PluginHost restart loses a running count and the widget
/// shows its idle face; PluginHost runs the plugin on one thread, so the lock is never contended.
final class StopwatchPlugin: PluginProvider {

    static let id      = PluginID(rawValue: "com.cascade.stopwatch")!
    static let feature = "stopwatch"

    private let now  : @Sendable () -> Date
    private let state = Mutex(StopwatchState.idle)

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        let date = now()

        let (before, after) = state.withLock { state in
            let before = state
            if case .action(let action) = event, action.feature == Self.feature {
                switch WidgetControl(action: action.action) {
                    case .start?: state = state.starting(at: date)
                    case .pause?: state = state.pausing(at: date)
                    case .reset?: state = state.resetting()
                    default     : break
                }
            }

            return (before, state)
        }
        guard before != after || event == .refresh else { return try PluginOutput() }

        return try PluginOutput(publications: [StopwatchFace.publication(for: after)])
    }
}
