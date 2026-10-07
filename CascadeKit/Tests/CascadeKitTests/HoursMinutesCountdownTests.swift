//
//  HoursMinutesCountdownTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeKit

@Suite
struct HoursMinutesCountdownTests {

    private let locale = Locale(identifier: "en_US")

    @Test(
        arguments: [
            (7200.0, "2h"),
            (3900.0, "1h 5m"),
            (3600.0, "1h"),
            (3599.0, "1h"),
            (3540.0, "59m"),
            (61.0,   "2m"),
            (60.0,   "1m"),
            (1.0,    "1m"),
            (0.0,    "0m"),
            (-5.0,   "0m"),
        ]
    )
    func hoursMinutesTextAtBoundaries(
        remaining: Double,
        expected : String
    ) {
        #expect(HoursMinutesCountdown.text(remaining: remaining, locale: locale) == expected)
    }

    @Test
    func aFifteenMinuteStepAlwaysChangesTheText() {
        for remaining in stride(from: 15.0 * 60 + 1, through: 24 * 3_600, by: 37) {
            let stepped = HoursMinutesCountdown.text(remaining: remaining - 15 * 60, locale: locale)

            #expect(HoursMinutesCountdown.text(remaining: remaining, locale: locale) != stepped)
        }
    }

    /// For starting remainders at and around every kind of boundary, the next entry must be
    /// exactly where the text really flips, found here by bisection on `text(remaining:)`
    /// itself, so that the test shares no arithmetic with `nextChange`.
    @Test(
        arguments: [7200.0, 3660.0, 3600.0, 120.0, 61.0, 60.0, 1.0],
        [-0.0005, 0.0, 0.0005]
    )
    func nextChangeIsWhereTheTextReallyFlips(
        boundary: Double,
        offset  : Double
    ) throws {
        let remaining = boundary + offset
        let end       = Date(timeIntervalSince1970: 1_800_000_000)
        let from      = end.addingTimeInterval(-remaining)
        let current   = HoursMinutesCountdown.text(remaining: remaining, locale: locale)
        let next      = try #require(HoursMinutesCountdown.nextChange(after: from, end: end))

        #expect(next > from)

        var lowest = remaining - 120
        var same   = remaining

        for _ in 0..<60 {
            let middle = (lowest + same) / 2

            if HoursMinutesCountdown.text(remaining: middle, locale: locale) == current {
                same = middle
            } else {
                lowest = middle
            }
        }

        #expect(abs(end.timeIntervalSince(next) - same) < 0.0015)
        #expect(HoursMinutesCountdown.text(remaining: end.timeIntervalSince(next), locale: locale) != current)
        #expect(
            HoursMinutesCountdown.text(remaining: end.timeIntervalSince(next.addingTimeInterval(-0.002)), locale: locale)
                == current
        )
    }

    /// The schedule yields the date the view appears and then exactly one entry per change of
    /// the text, each showing the next minute down, ending at `0m` just past the end.
    @Test
    func theScheduleYieldsOnlyTheChangeInstants() {
        let now     = Date(timeIntervalSince1970: 1_800_000_000)
        let end     = now.addingTimeInterval(3_725.4)
        let entries = Array(HoursMinutesCountdownSchedule(end: end).entries(from: now, mode: .normal))
        let texts   = entries.map { HoursMinutesCountdown.text(remaining: end.timeIntervalSince($0), locale: locale) }
        let scale   = (0...63).reversed().map { minutes in
            Duration.seconds(minutes * 60).formatted(
                .units(allowed: [.hours, .minutes], width: .narrow).locale(locale)
            )
        }

        #expect(entries.first == now)
        #expect(entries == entries.sorted())
        #expect(texts == scale)
        #expect(abs((entries.last ?? now).timeIntervalSince(end) - CompactCountdown.nudge) < 1e-6)
        #expect(zip(texts, texts.dropFirst()).allSatisfy { $0 != $1 })
    }

    @Test
    func theScheduleIsTheStartAloneForAPastEnd() {
        let from     = Date(timeIntervalSince1970: 1_800_000_000)
        let schedule = HoursMinutesCountdownSchedule(end: from.addingTimeInterval(-10))

        #expect(Array(schedule.entries(from: from, mode: .normal)) == [from])
        #expect(HoursMinutesCountdown.nextChange(after: from, end: from) == nil)
    }
}
