//
//  AudioVolumeCapsuleMetricsTests.swift
//  CascadeKit
//

import CoreGraphics
import Testing
@testable import CascadeKit

struct AudioVolumeCapsuleMetricsTests {

    @Test
    func theCapsuleKeepsTheReferenceProportionsInATallFrame() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: 100, availableHeight: 200, widthRatio: 0.6)

        #expect(abs(metrics.width - 94) < 0.001)   // height-bound: 200 × 0.47
        #expect(metrics.height == 200)
        #expect(metrics.cornerRadius == 47)
    }

    @Test
    func theCapsuleKeepsTheReferenceProportionsInAWideFrame() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: 47, availableHeight: 400, widthRatio: 0.6)

        #expect(metrics.width == 47)               // width-bound: never stretched
        #expect(abs(metrics.height - 100) < 0.001)
    }

    @Test
    func theIconAndTheTypeScaleWithTheCapsule() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: 60, availableHeight: 400, widthRatio: 0.6)

        #expect(abs(metrics.iconSize - 29.4) < 0.001)
        #expect(abs(metrics.symbolFontSize - 29.4) < 0.001)
        #expect(abs(metrics.iconCentre - 30.6) < 0.001)
        #expect(abs(metrics.iconInset - 15.9) < 0.001)
        #expect(abs(metrics.percentageFontSize - 33) < 0.001)
    }

    @Test
    func aTinyFrameKeepsAUsableCapsule() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: 10, availableHeight: 400, widthRatio: 0.6)

        #expect(metrics.width == 12)
        #expect(metrics.percentageFontSize == 9)
    }

    @Test
    func aCollapsedFrameStillAnswersWithoutNegativeSizes() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: -5, availableHeight: 400, widthRatio: 0.6)

        #expect(metrics.width == 12)
        #expect(metrics.cornerRadius == 6)
    }

    @Test
    func aFullRatioFillsTheFrameAsItAlwaysDid() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: 80, availableHeight: 200, widthRatio: 1)

        #expect(metrics.width == 80)
        #expect(metrics.cornerRadius == 40)
        #expect(abs(metrics.iconSize - 39.2) < 0.001)
    }

    @Test
    func aFullRatioIsNotRaisedToTheMinimum() {
        let metrics = AudioVolumeCapsuleMetrics(availableWidth: 8, availableHeight: 200, widthRatio: 1)

        #expect(metrics.width == 8)
    }
}
