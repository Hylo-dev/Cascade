//
//  CaffeinateStateTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct CaffeinateStateTests {

    @Test
    func targetValidation() {
        for minutes in [15, 30, 60, 1440] {
            #expect(CaffeinateTarget(kind: .duration, value: minutes) == .duration(minutes: minutes))
        }
        for minutes in [-15, 0, 10, 14, 1455, 1500, 7] {
            #expect(CaffeinateTarget(kind: .duration, value: minutes) == nil)
        }
        for minuteOfDay in [0, 15, 600, 1425] {
            #expect(CaffeinateTarget(kind: .until, value: minuteOfDay) == .until(minuteOfDay: minuteOfDay))
        }
        for minuteOfDay in [-15, 1, 14, 1430, 1440, 1455] {
            #expect(CaffeinateTarget(kind: .until, value: minuteOfDay) == nil)
        }
        #expect(CaffeinateTarget(kind: .indefinite, value: 0) == .indefinite)
        #expect(CaffeinateTarget(kind: .indefinite, value: 15) == nil)

        #expect(CaffeinateTarget.duration(minutes: 90).isValid)
        #expect(!CaffeinateTarget.duration(minutes: 91).isValid)
        #expect(!CaffeinateTarget.until(minuteOfDay: 1440).isValid)
        #expect(CaffeinateTarget.indefinite.isValid)
    }

    @Test
    func targetWireForm() {
        #expect(CaffeinateTarget.indefinite.kind == .indefinite)
        #expect(CaffeinateTarget.indefinite.value == 0)
        #expect(CaffeinateTarget.duration(minutes: 75).kind == .duration)
        #expect(CaffeinateTarget.duration(minutes: 75).value == 75)
        #expect(CaffeinateTarget.until(minuteOfDay: 1080).kind == .until)
        #expect(CaffeinateTarget.until(minuteOfDay: 1080).value == 1080)
        #expect(CaffeinateTargetKind.allCases.map(\.rawValue) == ["indefinite", "duration", "until"])
    }

    @Test
    func aDurationEndsThatManyMinutesAfterTheStart() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        #expect(CaffeinateTarget.indefinite.end(startingAt: start, calendar: utc) == nil)
        #expect(CaffeinateTarget.duration(minutes: 90).end(startingAt: start, calendar: utc) == start.addingTimeInterval(5_400))
    }

    @Test
    func anEndTimeIsTheNextOccurrenceAtLeastFifteenMinutesAhead() {
        // 2027-01-15 08:00:00 UTC.
        let start = Date(timeIntervalSince1970: 1_800_000_000)

        // 18:00 is later today.
        #expect(CaffeinateTarget.until(minuteOfDay: 18 * 60).end(startingAt: start, calendar: utc) == start.addingTimeInterval(10 * 3_600))
        // 08:15 is exactly fifteen minutes ahead: accepted.
        #expect(CaffeinateTarget.until(minuteOfDay: 8 * 60 + 15).end(startingAt: start, calendar: utc) == start.addingTimeInterval(900))
        // 08:00 is now, so tomorrow's.
        #expect(CaffeinateTarget.until(minuteOfDay: 8 * 60).end(startingAt: start, calendar: utc) == start.addingTimeInterval(86_400))
        // 06:00 has passed: tomorrow, across midnight.
        #expect(CaffeinateTarget.until(minuteOfDay: 6 * 60).end(startingAt: start, calendar: utc) == start.addingTimeInterval(22 * 3_600))
        // 00:00 is the next midnight.
        #expect(CaffeinateTarget.until(minuteOfDay: 0).end(startingAt: start, calendar: utc) == start.addingTimeInterval(16 * 3_600))
    }

    @Test
    func anEndTimeBarelyShortOfFifteenMinutesGoesToTomorrowButNeverPastADay() {
        // 08:00:30 UTC: 08:15 is 14 min 30 s ahead, so the next 08:15 is a day away, which the
        // cap holds to exactly a day after the start.
        let start = Date(timeIntervalSince1970: 1_800_000_030)

        #expect(CaffeinateTarget.until(minuteOfDay: 8 * 60 + 15).end(startingAt: start, calendar: utc) == start.addingTimeInterval(86_400))
    }

    @Test
    func anEndTimeFollowsTheWallClockAcrossADaylightSavingChange() throws {
        var newYork      = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        // 2027-03-13 20:00 EST (UTC-5), the evening before the spring-forward night.
        let start = try #require(newYork.date(from: DateComponents(year: 2027, month: 3, day: 13, hour: 20)))
        let end   = try #require(CaffeinateTarget.until(minuteOfDay: 8 * 60).end(startingAt: start, calendar: newYork))

        // 08:00 EDT the next morning is twelve hours of wall clock and eleven real ones.
        #expect(end.timeIntervalSince(start) == 11 * 3_600)
        #expect(newYork.dateComponents([.hour, .minute], from: end).hour == 8)

        // The fall-back night has an extra hour: twelve hours of wall clock are thirteen real ones.
        let evening = try #require(newYork.date(from: DateComponents(year: 2027, month: 11, day: 6, hour: 20)))
        let morning = try #require(CaffeinateTarget.until(minuteOfDay: 8 * 60).end(startingAt: evening, calendar: newYork))
        #expect(morning.timeIntervalSince(evening) == 13 * 3_600)
    }

    @Test
    func anEndTimeInTheHourTheClockSkipsEndsWhenTheClockNextShowsALaterOne() throws {
        var newYork      = Calendar(identifier: .gregorian)
        newYork.timeZone = try #require(TimeZone(identifier: "America/New_York"))

        // 02:30 does not exist on 2027-03-14.
        let start = try #require(newYork.date(from: DateComponents(year: 2027, month: 3, day: 13, hour: 20)))
        let end   = try #require(CaffeinateTarget.until(minuteOfDay: 2 * 60 + 30).end(startingAt: start, calendar: newYork))

        #expect(end > start.addingTimeInterval(900))
        #expect(end <= start.addingTimeInterval(86_400))
        #expect(newYork.component(.hour, from: end) == 3)
    }

    private var utc: Calendar {
        var calendar      = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    @Test
    func glyphsHaveAnOutlineVariant() {
        #expect(CaffeinateGlyph.allCases.map(\.filledSymbol) == ["cup.and.heat.waves.fill", "mug.fill", "pill.fill"])
        #expect(CaffeinateGlyph.allCases.map(\.outlineSymbol) == ["cup.and.heat.waves", "mug", "pill"])
    }

    @Test
    func eventRoundTrip() throws {
        let full = PluginCaffeinateState(
            startedAt        : Date(timeIntervalSince1970: 1_700_000_000),
            endsAt           : Date(timeIntervalSince1970: 1_700_003_600),
            activityStartedAt: Date(timeIntervalSince1970: 1_700_000_010),
            nextTarget       : .until(minuteOfDay: 1080),
            keepsDisplayAwake: false,
            glyph            : .pill,
            failure          : .extensionRefused(-5)
        )
        let timed      = PluginCaffeinateState(nextTarget: .duration(minutes: 90), failure: .assertionRefused(2))
        let defaults   = PluginCaffeinateState()

        for state in [full, timed, defaults] {
            #expect(PluginCaffeinateState(try state.event()) == state)
        }

        #expect(defaults.nextTarget == .indefinite)
        #expect(defaults.keepsDisplayAwake)
        #expect(defaults.glyph == .cupHeatWaves)
        #expect(!defaults.isActive)
        #expect(full.isActive)

        let fields = try defaults.event().fields
        #expect(fields["targetKind"] == .string("indefinite"))
        #expect(fields["targetValue"] == .number(0))
        #expect(fields["nextDuration"] == nil)
        #expect(try full.event().fields["targetKind"] == .string("until"))
        #expect(try full.event().fields["targetValue"] == .number(1080))
        #expect(fields["startedAt"] == nil)
        #expect(fields["endsAt"] == nil)
        #expect(fields["activityStartedAt"] == nil)
        #expect(fields["failure"] == nil)
    }

    @Test
    func eventRejectsInvalidFields() throws {
        let valid = try PluginCaffeinateState().event().fields

        func event(_ change: (inout [String: PluginValue]) -> Void) throws -> PluginSourceEvent {
            var fields = valid
            change(&fields)

            return try PluginSourceEvent(source: "caffeinate", fields: fields)
        }

        #expect(PluginCaffeinateState(try event { _ in }) != nil)
        #expect(PluginCaffeinateState(try event { $0["glyph"] = .string("bolt.fill") }) == nil)
        #expect(PluginCaffeinateState(try event { $0["targetValue"] = .number(7) }) == nil)
        #expect(PluginCaffeinateState(try event { $0["targetKind"] = .string("duration"); $0["targetValue"] = .number(0) }) == nil)
        #expect(PluginCaffeinateState(try event { $0["targetKind"] = .string("duration"); $0["targetValue"] = .number(90) }) != nil)
        #expect(PluginCaffeinateState(try event { $0["targetKind"] = .string("duration"); $0["targetValue"] = .number(1455) }) == nil)
        #expect(PluginCaffeinateState(try event { $0["targetKind"] = .string("duration"); $0["targetValue"] = .number(90.5) }) == nil)
        #expect(PluginCaffeinateState(try event { $0["targetKind"] = .string("until"); $0["targetValue"] = .number(1440) }) == nil)
        #expect(PluginCaffeinateState(try event { $0["targetKind"] = .string("until"); $0["targetValue"] = .number(1425) }) != nil)
        #expect(PluginCaffeinateState(try event { $0["targetKind"] = .string("indefinite"); $0["targetValue"] = .number(15) }) == nil)
        #expect(PluginCaffeinateState(try event { $0["targetKind"] = .string("forever") }) == nil)
        #expect(PluginCaffeinateState(try event { $0["targetKind"] = .number(1) }) == nil)
        #expect(PluginCaffeinateState(try event { $0["targetValue"] = .string("60") }) == nil)
        #expect(PluginCaffeinateState(try event { $0["targetKind"] = nil }) == nil)
        #expect(PluginCaffeinateState(try event { $0["targetValue"] = nil }) == nil)
        #expect(PluginCaffeinateState(try event { $0["failure"] = .string("assertionRefused") }) == nil)
        #expect(PluginCaffeinateState(try event { $0["failure"] = .string("exploded"); $0["failureCode"] = .number(1) }) == nil)
        #expect(PluginCaffeinateState(try event { $0["endsAt"] = .number(1e300) }) == nil)
        #expect(PluginCaffeinateState(try event { $0["endsAt"] = .string("soon") }) == nil)
        #expect(PluginCaffeinateState(try event { $0["keepsDisplayAwake"] = .number(1) }) == nil)

        // A non-finite number never reaches the decoder: the event itself refuses it.
        #expect(throws: (any Error).self) {
            try PluginSourceEvent(source: "caffeinate", fields: ["endsAt": .number(.infinity)])
        }

        let other = try PluginSourceEvent(source: "power", fields: valid)
        #expect(PluginCaffeinateState(other) == nil)
    }
}
