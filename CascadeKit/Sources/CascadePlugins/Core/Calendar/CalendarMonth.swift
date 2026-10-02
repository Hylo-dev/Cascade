//
//  CalendarMonth.swift
//  CascadeKit
//

import Foundation

/// CalendarMonth is the month around a date laid out as a wall calendar: its title, the weekday
/// initials in the order the user's first weekday sets, and whole weeks, from the first weekday
/// on or before the 1st to the last one after the month ends, so the grid takes 4 to 6 rows and
/// the days of the months around it fill the edges.
///
/// It is pure arithmetic on what the calendar says about one date: the day of the month, its
/// weekday and the length of this month and the one before. Walking the grid date by date would
/// cost a calendar computation per cell and meet the daylight-saving days on the way; the day
/// numbers never need them. Every name comes from the calendar's own locale, so the title, the
/// initials and the first weekday follow the user's settings without a string of ours.
struct CalendarMonth: Equatable, Sendable {

    /// Day is one cell of the grid.
    struct Day: Equatable, Sendable {

        let number   : Int
        let isInMonth: Bool
        let isToday  : Bool
    }

    let title          : String
    let weekdayInitials: [String]
    let weeks          : [[Day]]

    init(
        containing date: Date,
        calendar       : Calendar
    ) {
        let today        = calendar.component(.day, from: date)
        let weekday      = calendar.component(.weekday, from: date)
        let length       = calendar.range(of: .day, in: .month, for: date)?.count ?? today
        let lengthBefore = calendar.date(byAdding: .month, value: -1, to: date)
            .flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 31

        // The 1st falls `today - 1` days before the date, so its column is the date's weekday
        // stepped back that far, counted from the first weekday; both modulos keep it positive.
        let leadingDays = ((weekday - calendar.firstWeekday - (today - 1)) % 7 + 7) % 7
        let cells       = (leadingDays + length + 6) / 7 * 7

        let days = (0..<cells).map { cell in
            let dayOfMonth = cell - leadingDays + 1

            if dayOfMonth < 1 { return Day(number: lengthBefore + dayOfMonth, isInMonth: false, isToday: false) }
            if dayOfMonth > length { return Day(number: dayOfMonth - length, isInMonth: false, isToday: false) }

            return Day(number: dayOfMonth, isInMonth: true, isToday: dayOfMonth == today)
        }

        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let first   = min(max(calendar.firstWeekday - 1, 0), symbols.count)

        self.title           = date.formatted(Self.style(in: calendar).month(.wide).year())
        self.weekdayInitials = Array(symbols[first...] + symbols[..<first])
        self.weeks           = stride(from: 0, to: cells, by: 7).map { Array(days[$0..<$0 + 7]) }
    }

    /// style is a date format in the calendar's own locale, calendar and zone, so a date is named
    /// as the calendar that laid it out sees it, capitalised as a title, which matters in the
    /// languages that write months and weekdays in lower case.
    static func style(in calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(
            locale               : calendar.locale ?? .autoupdatingCurrent,
            calendar             : calendar,
            timeZone             : calendar.timeZone,
            capitalizationContext: .beginningOfSentence
        )
    }
}
