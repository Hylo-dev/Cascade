//
//  TimerPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Synchronization

/// TimerPlugin is the timer widget: set a length with +1 and +5 minutes, start it, pause, resume
/// and reset it, and a notice when it is done. The kernel draws every second of the countdown,
/// so the plugin runs only when a button is pressed and once at the timer's end, the wake every
/// output of a running timer asks for; an output without it would cancel it. The kernel posts
/// the wake once the end has come on its clock; one that still finds the timer running, as a
/// clock set back could make, publishes nothing and asks for the end again.
///
/// Every event first settles a timer whose end has come: the widget goes back to idle with
/// nothing set and the `finished` feature publishes its notice. A press that lands between the
/// end and the wake is so applied to the idle timer, as the user saw it. A press that changes
/// nothing publishes nothing. The state lives here behind a lock, so a PluginHost restart loses
/// a running timer and the widget shows its idle face; PluginHost runs the plugin on one thread,
/// so the lock is never contended.
final class TimerPlugin: PluginProvider {

    static let id       = PluginID(rawValue: "com.cascade.timer")!
    static let feature  = "timer"
    static let finished = "finished"

    private let now  : @Sendable () -> Date
    private let state = Mutex(TimerState.idle(duration: 0))

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
            if state.isFinished(at: date) { state = state.resetting() }
            if case .action(let action) = event,
               action.feature == Self.feature,
               let control = WidgetControl(action: action.action) {
                state = Self.applying(control, to: state, at: date)
            }

            return (before, state)
        }

        var publications: [PluginPublication] = []
        if before != after || event == .refresh {
            publications.append(try TimerFace.publication(for: after))
        }
        if before.isFinished(at: date) {
            publications.append(try TimerNotice.publication())
        }
        let wake: Date? = if case .running(let end, _) = after { end } else { nil }

        return try PluginOutput(publications: publications, wake: wake)
    }

    private static func applying(
        _ control: WidgetControl,
        to state : TimerState,
        at date  : Date
    ) -> TimerState {
        switch control {
            case .addOneMinute  : state.adding(60, at: date)
            case .addFiveMinutes: state.adding(300, at: date)
            case .start, .resume: state.starting(at: date)
            case .pause         : state.pausing(at: date)
            case .reset         : state.resetting()
        }
    }
}
