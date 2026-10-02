//
//  NextMidnight.swift
//  CascadeKit
//

import Foundation

/// nextMidnight is when the day after `date` begins in `calendar`, which is the only moment a
/// widget that shows a day needs to run again. It steps a calendar day forward and takes that
/// day's start rather than adding 24 hours, so a day that gains or loses an hour for daylight
/// saving still ends at midnight, and a day whose midnight a zone skips starts at its first
/// moment. A moment exactly at midnight waits for the next one. A calendar that cannot step a
/// day, which a real one never is, falls back to 24 hours later.
func nextMidnight(
    after date : Date,
    in calendar: Calendar
) -> Date {
    guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: date) else {
        return date.addingTimeInterval(86_400)
    }

    return calendar.startOfDay(for: tomorrow)
}
