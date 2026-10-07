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
        try change(remaining: 400,   boundary: 360)
        try change(remaining: 310,   boundary: 300)
        try change(remaining: 300,   boundary: 299)
        try change(remaining: 3600,  boundary: 3540)
        try change(remaining: 120.4, boundary: 120)
        #expect(CompactCountdown.nextChange(after: now, end: now) == nil)
    }

    @Test
    func nextChangeIsStrictlyLaterAndTheTextAtItIsNew() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let end = now.addingTimeInterval(3600)
        let next = try #require(CompactCountdown.nextChange(after: now, end: end))

        #expect(next > now)
        #expect(
            CompactCountdown.text(remaining: end.timeIntervalSince(next), locale: locale)
                != CompactCountdown.text(remaining: 3600, locale: locale)
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
    func everyEntryShowsANewText() {
        let now     = Date(timeIntervalSince1970: 1_800_000_000)
        let end     = now.addingTimeInterval(7_500.4)
        let entries = Array(CompactCountdownSchedule(end: end).entries(from: now, mode: .normal))
        let texts   = entries.map { CompactCountdown.text(remaining: end.timeIntervalSince($0), locale: locale) }

        for (previous, current) in zip(texts, texts.dropFirst().dropLast()) {
            #expect(previous != current)
        }

        #expect(texts.first == "2h")
        #expect(texts.last == "0:00")
        #expect(entries.count == 1 + 2 + 55 + 300)
    }

    @Test
    func scheduleIsEmptyForAPastEnd() {
        let from     = Date(timeIntervalSince1970: 1_800_000_000)
        let schedule = CompactCountdownSchedule(end: from.addingTimeInterval(-10))
        let entries  = Array(schedule.entries(from: from, mode: .normal))

        #expect(entries == [from])
    }
}
