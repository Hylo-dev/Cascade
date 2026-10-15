//
//  CalendarPlugin.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// CalendarPlugin is the calendar widget: today's weekday and day, or the month around it. What
/// it shows changes only when the day does, so it answers every event with today's face and a
/// wake at the next midnight, and runs once a day in between refreshes. Every event carries the
/// wake because an output without one would cancel it. It keeps no state: the clock and the
/// calendar are injected so tests can stand on any day, and the calendar defaults to the user's,
/// which follows their zone, locale and first weekday.
final class CalendarPlugin: PluginProvider {

    static let id      = PluginID(rawValue: "com.cascade.calendar")!
    static let feature = "calendar"

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
            publications: [CalendarFace.publication(at: date, in: calendar)],
            wake        : nextMidnight(after: date, in: calendar)
        )
    }
}
