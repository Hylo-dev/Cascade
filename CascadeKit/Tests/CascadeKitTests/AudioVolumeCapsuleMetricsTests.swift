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

        #expect(metrics.iconSize == 45)
        #expect(metrics.symbolFontSize == 33.75)
        #expect(metrics.iconInset == 30)
        #expect(metrics.percentageFontSize == 33)
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
        #expect(metrics.iconSize == 60)
    }

    @Test
    func aFullRatioIsNotRaisedToTheMinimum() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: 8, widthRatio: 1)

        #expect(metrics.width == 8)
    }
}
