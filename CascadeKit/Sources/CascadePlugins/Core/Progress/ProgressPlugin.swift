//
//  ProgressPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// ProgressPlugin is the progress widget: how much of today, this week, this month and this year
/// has gone. The kernel fills the bars from their periods, and every period ends at a midnight,
/// so the plugin answers every event with the periods around now and a wake at the next
/// midnight; the wake rides on every output because one without it would cancel it. It keeps no
/// state, and its clock and calendar are injected like the calendar widget's.
final class ProgressPlugin: PluginProvider {

    static let id      = PluginID(rawValue: "com.cascade.progress")!
    static let feature = "progress"

    private let now     : @Sendable () -> Date
    private let calendar: Calendar

    init(
        now     : @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.now      = now
        self.calendar = calendar
    }

    func handle(
        _ event: PluginEvent,
        context: PluginContext
    ) throws -> PluginOutput {
        let date = now()

        return try PluginOutput(
            publications: [ProgressFace.publication(for: ProgressPeriods(at: date, calendar: calendar))],
            wake        : nextMidnight(after: date, in: calendar)
        )
    }
}
