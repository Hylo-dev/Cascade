//
//  CaffeinatePlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Synchronization

/// CaffeinatePlugin is the keep-awake widget and its live activity. Cascade's native owner keeps
/// the session and publishes it as a snapshot on the `caffeinate` source; this plugin turns the
/// snapshot into documents and nothing else.
///
/// It publishes the widget whenever its document changes, and the activity while a session runs:
/// again whenever its content or attributes change, and withdrawn once when the session stops,
/// if one was out. A snapshot that changes nothing publishes nothing. The exception is the
/// ruler's range, which follows the clock, so a repeat that comes a quarter hour later is not
/// nothing; and while the widget's content depends on the clock it carries a `staleAfter`, so the
/// kernel asks for a `refresh` when the notch shows it stale. A `refresh`, which comes at start
/// and after a restart, gets the last documents again. So does the `caffeinate.options` action,
/// the press that opens the options page, but only as far as the documents differ: a page opened
/// minutes after the last snapshot starts on a range that begins in the future, at no wake of
/// its own.
///
/// The plugin never asks for a wake: the time left, the elapsed time and the end time are drawn
/// and kept current by the kernel, and any other action is a user's tap that the native owner
/// answers by name, so it returns an empty output and the owner's next snapshot is the answer.
///
/// Its only memory is the last snapshot and the two documents it last published. PluginHost
/// runs it on one thread, so the lock is never contended. `now` and `calendar` are read to build
/// the options page's ruler and the widget's end time, which are instants the plugin works out
/// from the snapshot (the next occurrence of a time of day, the range of the clock ruler), so a
/// test can pin both. The calendar is read at each publication, so a change of time zone shows
/// at the next one.
final class CaffeinatePlugin: PluginProvider {

    static let id      = PluginID(rawValue: "com.cascade.caffeinate")!
    static let feature = "awake"

    /// Activity is what the plugin knows of its live activity. A fresh plugin, such as one
    /// PluginHost just restarted, cannot know: the kernel may still hold the activity of a
    /// session that ended in the gap, so the first snapshot without a session withdraws it once.
    /// Withdrawing what is not there costs nothing.
    fileprivate enum Activity {

        case unknown
        case out(PluginPublication)
        case withdrawn
    }

    /// Memory is what the plugin keeps between events.
    private struct Memory {

        var state   : PluginCaffeinateState?
        var widget  : PluginPublication?
        var activity: Activity = .unknown
    }

    private let memory = Mutex(Memory())
    private let now     : @Sendable () -> Date
    private let calendar: @Sendable () -> Calendar

    init(
        now     : @escaping @Sendable () -> Date     = { Date() },
        calendar: @escaping @Sendable () -> Calendar = { Calendar.autoupdatingCurrent }
    ) {
        self.now      = now
        self.calendar = calendar
    }

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        switch event {
            case .source(let source):
                guard let state = PluginCaffeinateState(source) else { return try PluginOutput() }

                return try publish(state, force: false)

            case .refresh:
                guard let state = memory.withLock({ $0.state }) else { return try PluginOutput() }

                return try publish(state, force: true)

            case .action(let action) where action.action == CaffeinateStyle.Action.options:
                guard let state = memory.withLock({ $0.state }) else { return try PluginOutput() }

                return try publish(state, force: false)

            default:
                return try PluginOutput()
        }
    }

    /// publish builds the documents outside the lock, then records what it sends: only a
    /// document that differs from the last one goes out, unless `force` asks for the lot.
    private func publish(
        _ state: PluginCaffeinateState,
        force  : Bool
    ) throws -> PluginOutput {
        let moment = now()
        let widget = try CaffeinateWidgetFace.publication(
            for     : state,
            now     : moment,
            calendar: calendar()
        )
        let live   = state.isActive ? try CaffeinateActivityFace.publication(for: state, now: moment) : nil
        let ended  = try CaffeinateActivityFace.withdrawal()

        let publications = memory.withLock { memory -> [PluginPublication] in
            var out = [PluginPublication]()
            memory.state = state

            if force || memory.widget != widget {
                out.append(widget)
                memory.widget = widget
            }

            if let live {
                if force || !memory.activity.isOut(live) {
                    out.append(live)
                    memory.activity = .out(live)
                }
            } else if !memory.activity.isWithdrawn {
                out.append(ended)
                memory.activity = .withdrawn
            }

            return out
        }

        return try PluginOutput(publications: publications)
    }
}

private extension CaffeinatePlugin.Activity {

    func isOut(_ publication: PluginPublication) -> Bool {
        if case .out(let out) = self { out == publication } else { false }
    }

    var isWithdrawn: Bool {
        if case .withdrawn = self { true } else { false }
    }
}
