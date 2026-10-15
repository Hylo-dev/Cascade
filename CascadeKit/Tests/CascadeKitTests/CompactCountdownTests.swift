//
//  CompactCountdownTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeKit

@Suite
struct CompactCountdownTests {

    private let locale = Locale(identifier: "en_US")

    @Test(
        arguments: [
            (7200.0, "2h"),
            (3600.0, "1h"),
            (3599.0, "59m"),
            (300.0,  "5m"),
            (299.0,  "4:59"),
            (61.0,   "1:01"),
            (0.0,    "0:00"),
            (-5.0,   "0:00"),
        ]
    )
    func compactTextAtBoundaries(
        remaining: Double,
        expected : String
    ) {
        #expect(CompactCountdown.text(remaining: remaining, locale: locale) == expected)
    }

    @Test
    func nextChangeFollowsTheUnit() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        func change(
            remaining: TimeInterval,
            boundary : TimeInterval
        ) throws {
            let end  = now.addingTimeInterval(remaining)
            let next = try #require(CompactCountdown.nextChange(after: now, end: end))

            #expect(abs(next.timeIntervalSince(end.addingTimeInterval(-boundary))) < 0.01)
        }

        try change(remaining: 7230,  boundary: 7200)
        try change(remaining: 7200,  boundary: 7200)
        try change(remaining: 3600,  boundary: 3600)
        try change(remaining: 400,   boundary: 360)
        try change(remaining: 360,   boundary: 360)
        try change(remaining: 310,   boundary: 300)
        try change(remaining: 300,   boundary: 300)
        try change(remaining: 120.4, boundary: 120)
        try change(remaining: 120,   boundary: 120)
        try change(remaining: 1,     boundary: 1)
        #expect(CompactCountdown.nextChange(after: now, end: now) == nil)
    }

    @Test
    func theTextAtTheNextChangeIsTheImmediatelyNextValue() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        for (remaining, before, after) in [
            (7200.0, "2h",   "1h"),
            (3600.0, "1h",   "59m"),
            (360.0,  "6m",   "5m"),
            (300.0,  "5m",   "4:59"),
            (120.0,  "2:00", "1:59"),
            (1.0,    "0:01", "0:00"),
        ] {
            let end  = now.addingTimeInterval(remaining)
            let next = try #require(CompactCountdown.nextChange(after: now, end: end))

            #expect(next > now)
            #expect(CompactCountdown.text(remaining: remaining, locale: locale) == before)
            #expect(CompactCountdown.text(remaining: end.timeIntervalSince(next), locale: locale) == after)
        }
    }

    /// For starting remainders at and around every boundary, the next entry must be exactly where
    /// the text really flips, found here by bisection on `text(remaining:)` itself, so that the
    /// test shares no arithmetic with `nextChange`: nothing stale before it, nothing skipped.
    @Test(
        arguments: [7200.0, 3600.0, 360.0, 300.0, 120.0, 1.0],
        [-0.0005, 0.0, 0.0005]
    )
    func nextChangeIsWhereTheTextReallyFlips(
        boundary: Double,
        offset  : Double
    ) throws {
        let remaining = boundary + offset
        let end       = Date(timeIntervalSince1970: 1_800_000_000)
        let from      = end.addingTimeInterval(-remaining)
        let current   = CompactCountdown.text(remaining: remaining, locale: locale)
        let next      = try #require(CompactCountdown.nextChange(after: from, end: end))

        #expect(next > from)

        var lowest = remaining - 3_700
        var same   = remaining

        if CompactCountdown.text(remaining: lowest, locale: locale) == current {
            #expect(abs(next.timeIntervalSince(end) - CompactCountdown.nudge) < 1e-6)
            return
        }

        for _ in 0..<60 {
            let middle = (lowest + same) / 2

            if CompactCountdown.text(remaining: middle, locale: locale) == current {
                same = middle
            } else {
                lowest = middle
            }
        }

        #expect(abs(end.timeIntervalSince(next) - same) < 0.0015)
        #expect(CompactCountdown.text(remaining: end.timeIntervalSince(next), locale: locale) != current)
        #expect(
            CompactCountdown.text(remaining: end.timeIntervalSince(next.addingTimeInterval(-0.002)), locale: locale)
                == current
        )
    }

    @Test
    func scheduleStartsAtFromAndEndsAtTheEnd() {
        let now      = Date(timeIntervalSince1970: 1_800_000_000)
        let end      = now.addingTimeInterval(302)
        let schedule = CompactCountdownSchedule(end: end)
        let entries  = Array(schedule.entries(from: now, mode: .normal))

        #expect(entries.first == now)
        #expect(abs((entries.last ?? now).timeIntervalSince(end)) < 0.01)
        #expect(entries.count <= 305)
        #expect(entries == entries.sorted())
    }

    @Test
    func everyEntryShowsTheNextValueOfTheScale() {
        let now     = Date(timeIntervalSince1970: 1_800_000_000)
        let end     = now.addingTimeInterval(7_500.4)
        let entries = Array(CompactCountdownSchedule(end: end).entries(from: now, mode: .normal))
        let texts   = entries.map { CompactCountdown.text(remaining: end.timeIntervalSince($0), locale: locale) }

        var scale = ["2h", "1h"]

        scale += (5...59).reversed().map { "\($0)m" }
        scale += (0...299).reversed().map { "\($0 / 60):" + String(format: "%02d", $0 % 60) }
        scale += ["0:00"]

        #expect(texts == scale)
    }

    @Test
    func scheduleIsEmptyForAPastEnd() {
        let from     = Date(timeIntervalSince1970: 1_800_000_000)
        let schedule = CompactCountdownSchedule(end: from.addingTimeInterval(-10))
        let entries  = Array(schedule.entries(from: from, mode: .normal))

        #expect(entries == [from])
    }
}
