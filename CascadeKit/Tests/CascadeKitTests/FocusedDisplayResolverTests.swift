//
//  FocusedDisplayResolverTests.swift
//  CascadeKit
//

import CoreGraphics
import Foundation
import Testing
@testable import CascadeKit

nonisolated struct FocusedDisplayResolverTests {

    private let frames: [CGDirectDisplayID: CGRect] = [
        1: CGRect(x: 0, y: 0, width: 1_000, height: 800),
        2: CGRect(x: -1_000, y: 0, width: 1_000, height: 800),
        3: CGRect(x: 0, y: 800, width: 1_000, height: 800),
    ]

    @Test
    func focusedWindowWinsOverPointer() {
        #expect(FocusedDisplayResolver.resolve(
            window  : CGRect(x: -900, y: 100, width: 600, height: 500),
            pointer : CGPoint(x: 500, y: 400),
            frames  : frames,
            previous: 1,
            main    : 1
        ) == 2)
        #expect(FocusedDisplayResolver.resolve(
            window  : nil,
            pointer : CGPoint(x: 500, y: 400),
            frames  : frames,
            previous: 2,
            main    : 1
        ) == 1)
    }

    @Test
    func largestIntersectionWinsAndPreviousBreaksAnAreaTie() {
        #expect(FocusedDisplayResolver.resolve(
            window  : CGRect(x: -300, y: 100, width: 800, height: 400),
            pointer : CGPoint(x: -500, y: 400),
            frames  : frames,
            previous: 2,
            main    : 1
        ) == 1)
        #expect(FocusedDisplayResolver.resolve(
            window  : CGRect(x: -500, y: 100, width: 1_000, height: 400),
            pointer : CGPoint(x: 500, y: 400),
            frames  : frames,
            previous: 2,
            main    : 1
        ) == 2)
        #expect(FocusedDisplayResolver.resolve(
            window  : CGRect(x: -500, y: 100, width: 1_000, height: 400),
            pointer : CGPoint(x: 500, y: 400),
            frames  : frames,
            previous: nil,
            main    : 1
        ) == 1)
    }

    @Test
    func invalidGeometryFallsBackWithoutKeepingAStaleWindowDisplay() {
        let invalidFrames: [CGDirectDisplayID: CGRect] = [
            7: CGRect(x: CGFloat.infinity, y: 0, width: 100, height: 100),
            8: .null,
            9: CGRect(x: 2_000, y: 0, width: 0, height: 100),
            4: CGRect(x: 0, y: 0, width: 100, height: 100),
        ]

        #expect(FocusedDisplayResolver.resolve(
            window  : CGRect(x: 500, y: 500, width: 100, height: 100),
            pointer : CGPoint(x: 10, y: 10),
            frames  : invalidFrames,
            previous: 7,
            main    : 7
        ) == 4)
        #expect(FocusedDisplayResolver.resolve(
            window  : CGRect(x: CGFloat.nan, y: 0, width: 100, height: 100),
            pointer : CGPoint(x: CGFloat.nan, y: 10),
            frames  : invalidFrames,
            previous: 4,
            main    : 7
        ) == 4)
        #expect(FocusedDisplayResolver.resolve(
            window  : nil,
            pointer : CGPoint(x: CGFloat.nan, y: CGFloat.nan),
            frames  : [:],
            previous: 4,
            main    : 7
        ) == nil)
    }

    @Test
    func accessibilityFramesNormalizeAcrossTheWholeDesktop() {
        #expect(FocusedWindowCoordinateSpace.appKitFrame(
            fromAXFrame: CGRect(x: 100, y: 100, width: 400, height: 300),
            desktopTop : 900
        ) == CGRect(x: 100, y: 500, width: 400, height: 300))
        #expect(FocusedWindowCoordinateSpace.appKitFrame(
            fromAXFrame: CGRect(x: 50, y: -700, width: 400, height: 400),
            desktopTop : 900
        ) == CGRect(x: 50, y: 1_200, width: 400, height: 400))
        #expect(FocusedWindowCoordinateSpace.appKitFrame(
            fromAXFrame: CGRect(x: 50, y: 1_000, width: 400, height: 300),
            desktopTop : 900
        ) == CGRect(x: 50, y: -400, width: 400, height: 300))
        #expect(FocusedWindowCoordinateSpace.appKitFrame(
            fromAXFrame: CGRect(x: -900, y: 200, width: 500, height: 300),
            desktopTop : 900
        ) == CGRect(x: -900, y: 400, width: 500, height: 300))
        #expect(FocusedWindowCoordinateSpace.appKitFrame(
            fromAXFrame: CGRect(x: 0, y: 0, width: 0, height: 300),
            desktopTop : 900
        ) == nil)
    }
}
