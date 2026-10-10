//
//  AudioVolumeCapsuleMetricsTests.swift
//  CascadeKit
//

import CoreGraphics
import Testing
@testable import CascadeKit

struct AudioVolumeCapsuleMetricsTests {

    @Test
    func theCapsuleIsSixtyPercentOfTheFrame() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: 100, widthRatio: 0.6)

        #expect(metrics.width == 60)
        #expect(metrics.cornerRadius == 30)
    }

    @Test
    func theIconAndTheTypeScaleWithTheCapsule() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: 100, widthRatio: 0.6)

        #expect(abs(metrics.iconSize - 29.4) < 0.001)
        #expect(abs(metrics.symbolFontSize - 29.4) < 0.001)
        #expect(abs(metrics.iconCentre - 30.6) < 0.001)
        #expect(abs(metrics.iconInset - 15.9) < 0.001)
        #expect(abs(metrics.percentageFontSize - 33) < 0.001)
    }

    @Test
    func aTinyFrameKeepsAUsableCapsule() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: 10, widthRatio: 0.6)

        #expect(metrics.width == 12)
        #expect(metrics.percentageFontSize == 9)
    }

    @Test
    func aCollapsedFrameStillAnswersWithoutNegativeSizes() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: -5, widthRatio: 0.6)

        #expect(metrics.width == 12)
        #expect(metrics.cornerRadius == 6)
    }

    @Test
    func aFullRatioFillsTheFrameAsItAlwaysDid() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: 80, widthRatio: 1)

        #expect(metrics.width == 80)
        #expect(metrics.cornerRadius == 40)
        #expect(abs(metrics.iconSize - 39.2) < 0.001)
    }

    @Test
    func aFullRatioIsNotRaisedToTheMinimum() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: 8, widthRatio: 1)

        #expect(metrics.width == 8)
    }
}
