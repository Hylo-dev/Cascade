//
//  TestCalendar.swift
//  CascadeKit
//

import Foundation
import Testing

/// TestCalendar is the calendar the date tests run in, so none of them depends on the machine's
/// settings or on today: Gregorian, in English, with the first weekday each test says, usually in
/// Rome's zone, which changes hour on 29 March and on 25 October 2026.
enum TestCalendar {

    static func rome(firstWeekday: Int = 2) throws -> Calendar {
        try calendar(in: "Europe/Rome", firstWeekday: firstWeekday)
    }

    static func calendar(
        in zone     : String,
        firstWeekday: Int = 2
    ) throws -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone     = try #require(TimeZone(identifier: zone))
        calendar.locale       = Locale(identifier: "en_US")
        calendar.firstWeekday = firstWeekday

        return calendar
    }

    /// date is a wall-clock moment in `calendar`'s zone.
    static func date(
        _ year  : Int,
        _ month : Int,
        _ day   : Int,
        _ hour  : Int = 0,
        _ minute: Int = 0,
        in calendar: Calendar
    ) throws -> Date {
        try #require(
            calendar.date(
                from: DateComponents(
                    year  : year,
                    month : month,
                    day   : day,
                    hour  : hour,
                    minute: minute
                )
            )
        )
    }
}
