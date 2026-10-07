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
    func durationScale() {
        #expect(CaffeinateDuration.indefinite.steppedUp() == .minutes(15))
        #expect(CaffeinateDuration.minutes(15).steppedDown() == .indefinite)
        #expect(CaffeinateDuration.indefinite.steppedDown() == nil)
        #expect(CaffeinateDuration.minutes(1440).steppedUp() == nil)
        #expect(CaffeinateDuration.minutes(45).steppedUp() == .minutes(60))
        #expect(CaffeinateDuration.minutes(60).steppedDown() == .minutes(45))
        #expect(CaffeinateDuration.indefinite.seconds == nil)
        #expect(CaffeinateDuration.minutes(90).seconds == 5_400)
    }

    @Test
    func wireMinutesRejectsOffScale() {
        for minutes in [-15, 10, 1455, 7] {
            #expect(CaffeinateDuration(wireMinutes: minutes) == nil)
        }
        #expect(CaffeinateDuration(wireMinutes: 0) == .indefinite)
        #expect(CaffeinateDuration(wireMinutes: 15) == .minutes(15))
        #expect(CaffeinateDuration(wireMinutes: 1440) == .minutes(1440))
        #expect(CaffeinateDuration.indefinite.wireMinutes == 0)
        #expect(CaffeinateDuration.minutes(75).wireMinutes == 75)
    }

    @Test
    func timeLeftRoundsUp() {
        #expect(CaffeinateDuration.timeLeft(600) == .minutes(15))
        #expect(CaffeinateDuration.timeLeft(901) == .minutes(30))
        #expect(CaffeinateDuration.timeLeft(5_400) == .minutes(90))
        #expect(CaffeinateDuration.timeLeft(200_000) == .minutes(1440))
        #expect(CaffeinateDuration.timeLeft(0) == .minutes(15))
        #expect(CaffeinateDuration.timeLeft(-30) == .minutes(15))
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
            nextDuration     : .minutes(90),
            keepsDisplayAwake: false,
            glyph            : .pill,
            failure          : .extensionRefused(-5)
        )
        let indefinite = PluginCaffeinateState(nextDuration: .indefinite, failure: .assertionRefused(2))
        let defaults   = PluginCaffeinateState()

        for state in [full, indefinite, defaults] {
            #expect(PluginCaffeinateState(try state.event()) == state)
        }

        #expect(defaults.nextDuration == .minutes(60))
        #expect(defaults.keepsDisplayAwake)
        #expect(defaults.glyph == .cupHeatWaves)
        #expect(!defaults.isActive)
        #expect(full.isActive)

        let fields = try defaults.event().fields
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
        #expect(PluginCaffeinateState(try event { $0["nextDuration"] = .number(7) }) == nil)
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
