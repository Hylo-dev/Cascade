//
//  RulerGeometryTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeKit

@Suite
struct RulerGeometryTests {

    private let width   = 260.0
    private let spacing = 13.0

    private func ticks(
        value  : Double,
        minimum: Double = 15,
        maximum: Double = 1_440,
        step   : Double = 15,
        origin : Double = 0
    ) -> [RulerTick] {
        RulerGeometry.ticks(
            value  : value,
            minimum: minimum,
            maximum: maximum,
            step   : step,
            width  : width,
            spacing: spacing,
            origin : origin
        )
    }

    @Test
    func theTickUnderTheIndicatorIsFullHeightAndFullAlpha() throws {
        let centre = try #require(ticks(value: 90).first { $0.offset == 0 })

        #expect(centre.heightFraction == 1)
        #expect(centre.alpha == 1)
        #expect(centre.isPassed)
    }

    @Test
    func theFalloffIsSymmetricAroundTheIndicator() throws {
        let all = ticks(value: 720)

        for tick in all where tick.offset > 0 {
            let mirror = try #require(all.first { $0.offset == -tick.offset })

            #expect(mirror.alpha == tick.alpha)
            #expect(mirror.heightFraction == tick.heightFraction)
        }
    }

    @Test
    func heightAndAlphaFallWithTheDistanceFromTheIndicator() {
        let right = ticks(value: 720).filter { $0.offset >= 0 }.sorted { $0.offset < $1.offset }

        for (nearer, farther) in zip(right, right.dropFirst()) {
            #expect(farther.alpha < nearer.alpha)
            #expect(farther.heightFraction < nearer.heightFraction)
        }
    }

    @Test
    func theEdgeFadesOutAndKeepsAboutFortyFivePercentOfTheHeight() throws {
        let farthest = try #require(ticks(value: 720).max { $0.offset < $1.offset })

        #expect(farthest.alpha >= 0)
        #expect(farthest.alpha < 0.1)
        #expect(farthest.heightFraction > 0.45)
        #expect(farthest.heightFraction < 0.55)
    }

    @Test
    func aTickIsPassedWhenTheValueHasReachedIt() {
        for tick in ticks(value: 97.5) {
            #expect(tick.isPassed == (tick.offset <= 0))
        }
    }

    @Test
    func aFractionalValueShiftsTheTicksByTheFraction() {
        let offsets = ticks(value: 97.5).map(\.offset)

        #expect(offsets.contains(-6.5))
        #expect(offsets.contains(6.5))
        #expect(!offsets.contains(0))
    }

    @Test
    func ticksOutsideTheRangeAreOmitted() throws {
        let atStart = ticks(value: 15)
        let atEnd   = ticks(value: 1_440)

        #expect(try #require(atStart.min { $0.offset < $1.offset }).offset == 0)
        #expect(try #require(atEnd.max { $0.offset < $1.offset }).offset == 0)
    }

    @Test(arguments: [15.0, 22.0, 90.0, 97.5, 720.0, 1_433.0, 1_440.0])
    func atMostAScreenfulOfTicksIsProduced(value: Double) {
        let limit = Int((width / spacing).rounded(.up)) + 2

        #expect(ticks(value: value).count <= limit)
        #expect(!ticks(value: value).isEmpty)
    }

    @Test
    func theLabelIndexIsTheTicksAbsoluteStepOrdinal() throws {
        let hour = try #require(ticks(value: 90).first { $0.offset == -30 * spacing / 15 })

        #expect(hour.labelIndex == 4)
    }

    @Test
    func theOriginShiftsTheOrdinalForALocalClockLabelledOnTheHour() throws {
        let shifted = try #require(ticks(value: 90, origin: 45).first { $0.offset == 0 })

        #expect(shifted.labelIndex == 9)
    }

    @Test
    func aDegenerateRulerDrawsNothing() {
        #expect(ticks(value: 5, minimum: 5, maximum: 5).isEmpty)
        #expect(ticks(value: 5, step: 0).isEmpty)
        #expect(RulerGeometry.ticks(value: 5, minimum: 0, maximum: 10, step: 1, width: 0, spacing: 13).isEmpty)
    }

    @Test
    func theValueSnapsToTheNearestStepInsideTheRange() {
        #expect(RulerGeometry.snapped(97, minimum: 15, maximum: 1_440, step: 15) == 90)
        #expect(RulerGeometry.snapped(98, minimum: 15, maximum: 1_440, step: 15) == 105)
        #expect(RulerGeometry.snapped(0, minimum: 15, maximum: 1_440, step: 15) == 15)
        #expect(RulerGeometry.snapped(5_000, minimum: 15, maximum: 1_440, step: 15) == 1_440)
    }

    @Test
    func draggingLeftRaisesTheValue() {
        let raised = RulerGeometry.dragged(from: 90, translation: -26, minimum: 15, maximum: 1_440, step: 15, spacing: 13)
        let lowered = RulerGeometry.dragged(from: 90, translation: 26, minimum: 15, maximum: 1_440, step: 15, spacing: 13)
        let clamped = RulerGeometry.dragged(from: 90, translation: 100_000, minimum: 15, maximum: 1_440, step: 15, spacing: 13)

        #expect(raised == 120)
        #expect(lowered == 60)
        #expect(clamped == 15)
    }
}

@Suite
struct RulerLabelTests {

    @Test(arguments: [(60.0, "1h"), (90.0, "1h 30m"), (120.0, "2h"), (15.0, "15m"), (1_440.0, "24h")])
    func aDurationReadsInHoursAndMinutes(minutes: Double, expected: String) {
        let text = RulerLabel.text(
            value : minutes,
            labels: .duration,
            locale: Locale(identifier: "en_US")
        )

        #expect(text == expected)
    }

    @Test
    func aClockTimeReadsInTheLocalesShortTime() {
        let evening = Date(timeIntervalSince1970: 1_800_000_000)
        let zone    = TimeZone(identifier: "Europe/Rome") ?? .gmt
        let locale  = Locale(identifier: "en_GB")
        let text    = RulerLabel.text(
            value   : evening.timeIntervalSince1970,
            labels  : .clockTime,
            locale  : locale,
            timeZone: zone
        )
        let expected = evening.formatted(
            Date.FormatStyle(
                date    : .omitted,
                time    : .shortened,
                locale  : locale,
                timeZone: zone
            )
        )

        #expect(text == expected)
        #expect(text.contains(":"))
    }

    @Test
    func aClockTimeOnTheHourIsWrittenAsTheHour() {
        let text = RulerLabel.text(
            value   : 64_800,
            labels  : .clockTime,
            locale  : Locale(identifier: "en_GB"),
            timeZone: .gmt
        )

        #expect(text == "18:00")
    }

    @Test(arguments: [(60.0, "1 hour"), (90.0, "1 hour, 30 minutes"), (15.0, "15 minutes"), (1_440.0, "24 hours")])
    func aDurationIsSpokenInFull(minutes: Double, expected: String) {
        let text = RulerLabel.spoken(
            value : minutes,
            labels: .duration,
            locale: Locale(identifier: "en_US")
        )

        #expect(text == expected)
    }

    @Test
    func aDurationIsSpokenInFullInTheLocalesOwnWords() {
        let text = RulerLabel.spoken(
            value : 90,
            labels: .duration,
            locale: Locale(identifier: "it_IT")
        )

        #expect(text.contains("ora"))
        #expect(text.contains("minuti"))
    }

    @Test
    func aClockTimeIsSpokenAsTheShortTime() {
        let spoken = RulerLabel.spoken(
            value   : 64_800,
            labels  : .clockTime,
            locale  : Locale(identifier: "en_GB"),
            timeZone: .gmt
        )

        #expect(spoken == "18:00")
    }

    @MainActor
    @Test
    func theCacheKeepsTheDrawnAndTheSpokenFormsApart() {
        let cache = RulerLabelCache()

        let drawn  = cache.text(value: 90, labels: .duration)
        let spoken = cache.spoken(value: 90, labels: .duration)

        #expect(drawn == RulerLabel.text(value: 90, labels: .duration))
        #expect(spoken == RulerLabel.spoken(value: 90, labels: .duration))
        #expect(drawn != spoken)
        #expect(cache.text(value: 90, labels: .duration) == drawn)
    }
}
