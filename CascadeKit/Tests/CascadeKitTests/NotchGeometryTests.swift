//
//  NotchGeometryTests.swift
//  CascadeKitTests
//

import Testing
import CoreGraphics
@testable import CascadeKit

/// NotchGeometry.resolve is pure math, so it is the easiest part of the morph
/// to nail down: at progress 0 it must equal the resting notch, at 1 the
/// configured expansion, and the two sides must be free to disagree.
struct NotchGeometryTests {

    private let configuration = NotchConfiguration.default

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
}
