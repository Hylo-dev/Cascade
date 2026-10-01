//
//  NotchGeometryTests.swift
//  CascadeKit
//

import Testing
import CoreGraphics
@testable import CascadeKit

/// NotchGeometryTests nails down NotchGeometry.resolve, the easiest part of the
/// morph because it is pure math: at progress 0 it must equal the resting notch,
/// at 1 the configured expansion, and the two sides must be free to disagree.
struct NotchGeometryTests {

    private let configuration = NotchConfiguration.default

    @Test
    func cornersRoundAheadOfExpansionAndStaySoftDuringClosure() {
        var previousRadius = configuration.restingBottomCornerRadius

        for progress in [CGFloat(0.1), 0.25, 0.5, 0.75, 0.9] {
            let geometry = NotchGeometry.resolve(
                configuration   : configuration,
                restingHalfWidth: 100,
                restingHeight   : 30,
                leadingProgress : progress,
                trailingProgress: progress
            )
            let linearRadius = configuration.restingBottomCornerRadius
                + (configuration.expandedBottomCornerRadius - configuration.restingBottomCornerRadius) * progress

            #expect(geometry.bottomCornerRadius > linearRadius)
            #expect(geometry.bottomCornerRadius > previousRadius)
            #expect(geometry.bottomCornerRadius <= configuration.expandedBottomCornerRadius)

            previousRadius = geometry.bottomCornerRadius
        }
    }

    @Test
    func compactActivityWidensSidesWithoutOpeningTheWidgetSurface() {
        let geometry = NotchGeometry.resolve(
            configuration           : configuration,
            restingHalfWidth        : 100,
            restingHeight           : 30,
            compactLeadingExtension : 60,
            compactTrailingExtension: 40,
            leadingProgress         : 0,
            trailingProgress        : 0
        )

        #expect(geometry.leftExtent == 160)
        #expect(geometry.rightExtent == 140)
        #expect(geometry.height == 30)
    }

    @Test
    func restingProgressMatchesTheRestingNotch() {
        let geometry = NotchGeometry.resolve(
            configuration   : configuration,
            restingHalfWidth: 100,
            restingHeight   : 30,
            leadingProgress : 0,
            trailingProgress: 0
        )

        #expect(geometry.leftExtent  == 100)
        #expect(geometry.rightExtent == 100)
        #expect(geometry.height      == 30)
    }

    @Test
    func fullProgressReachesTheConfiguredExpansion() {
        let geometry = NotchGeometry.resolve(
            configuration   : configuration,
            restingHalfWidth: 100,
            restingHeight   : 30,
            leadingProgress : 1,
            trailingProgress: 1
        )

        #expect(geometry.leftExtent  == configuration.expandedHalfWidth)
        #expect(geometry.rightExtent == configuration.expandedHalfWidth)
        #expect(geometry.height      == configuration.expandedHeight)
    }

    @Test
    func oneSideCanExpandWhileTheOtherRests() {
        let geometry = NotchGeometry.resolve(
            configuration   : configuration,
            restingHalfWidth: 100,
            restingHeight   : 30,
            leadingProgress : 1,
            trailingProgress: 0
        )

        #expect(geometry.leftExtent  == configuration.expandedHalfWidth)
        #expect(geometry.rightExtent == 100)
        // Height follows whichever side is more open.
        #expect(geometry.height      == configuration.expandedHeight)
    }

    @Test
    func adaptiveDimensionsOverrideOnlyTheirIndependentGeometryAxes() {
        let geometry = NotchGeometry.resolve(
            configuration    : configuration,
            restingHalfWidth : 100,
            restingHeight    : 30,
            expandedHalfWidth: 190,
            resolvedHeight   : 102,
            leadingProgress  : 1,
            trailingProgress : 1
        )

        #expect(geometry.leftExtent == 190)
        #expect(geometry.rightExtent == 190)
        #expect(geometry.height == 102)
        #expect(geometry.bottomCornerRadius == configuration.expandedBottomCornerRadius)
    }
}
