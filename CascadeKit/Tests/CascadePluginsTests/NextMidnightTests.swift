//
//  NextMidnightTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadePlugins

@Suite
struct NextMidnightTests {

    @Test
    func theNextMidnightIsTheStartOfTomorrow() throws {
        let rome = try TestCalendar.rome()

        let midnight = nextMidnight(after: try TestCalendar.date(2026, 10, 24, 22, in: rome), in: rome)

        #expect(midnight == (try TestCalendar.date(2026, 10, 25, in: rome)))
    }

    @Test
    func aDayThatGainsAnHourEndsTwentyFiveHoursAfterItBegan() throws {
        let rome  = try TestCalendar.rome()
        let start = try TestCalendar.date(2026, 10, 25, in: rome)

        let midnight = nextMidnight(after: try TestCalendar.date(2026, 10, 25, 12, in: rome), in: rome)

        #expect(midnight == (try TestCalendar.date(2026, 10, 26, in: rome)))
        #expect(midnight.timeIntervalSince(start) == 25 * 3_600)
    }

    @Test
    func aDayThatLosesAnHourEndsTwentyThreeHoursAfterItBegan() throws {
        let rome  = try TestCalendar.rome()
        let start = try TestCalendar.date(2026, 3, 29, in: rome)

        let midnight = nextMidnight(after: try TestCalendar.date(2026, 3, 29, 12, in: rome), in: rome)

        #expect(midnight == (try TestCalendar.date(2026, 3, 30, in: rome)))
        #expect(midnight.timeIntervalSince(start) == 23 * 3_600)
    }

    @Test
    func aMomentAtMidnightWaitsForTheNextOne() throws {
        let rome = try TestCalendar.rome()

        let midnight = nextMidnight(after: try TestCalendar.date(2026, 10, 2, in: rome), in: rome)

        #expect(midnight == (try TestCalendar.date(2026, 10, 3, in: rome)))
    }
}
