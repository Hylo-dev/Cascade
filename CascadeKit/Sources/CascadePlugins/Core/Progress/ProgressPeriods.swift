//
//  ProgressPeriods.swift
//  CascadeKit
//

import Foundation

/// ProgressPeriods are the day, the week, the month and the year a moment falls in, each from its
/// first instant to the first instant of the next, as the calendar counts them: the week starts
/// on the user's first weekday, and a day that gains or loses an hour for daylight saving is 25
/// or 23 hours long. Every period ends at a midnight, so a face drawn from them stays right
/// until the next one. A calendar that cannot place the moment, which a real one never is,
/// leaves that period empty at the moment itself rather than inventing one.
struct ProgressPeriods: Equatable, Sendable {

    let day  : ClosedRange<Date>
    let week : ClosedRange<Date>
    let month: ClosedRange<Date>
    let year : ClosedRange<Date>

    init(
        at date : Date,
        calendar: Calendar
    ) {
        func period(_ component: Calendar.Component) -> ClosedRange<Date> {
            guard let interval = calendar.dateInterval(of: component, for: date) else { return date...date }

            return interval.start...interval.end
        }

        self.day   = period(.day)
        self.week  = period(.weekOfYear)
        self.month = period(.month)
        self.year  = period(.year)
    }
}
