//
//  VolumeGestureTests.swift
//  CascadeKit
//

import CoreGraphics
import Testing
@testable import CascadeKit

struct VolumeGestureTests {

    @Test
    func pressReleasedWithinSlopBeforeHoldIsAClick() {
        var gesture = VolumeGesture(startLevel: 0.5, travel: 100)

        let outcome = gesture.end(translation: CGSize(width: 1, height: 2), elapsed: .milliseconds(200))

        #expect(outcome == .click)
    }

    @Test
    func heldStillPressIsNeitherClickNorDrag() {
        var gesture = VolumeGesture(startLevel: 0.5, travel: 100)

        let outcome = gesture.end(translation: .zero, elapsed: .milliseconds(600))

        #expect(outcome == .none)
    }

    @Test
    func movesWithinSlopChangeNothing() {
        var gesture = VolumeGesture(startLevel: 0.5, travel: 100)

        #expect(gesture.move(to: CGSize(width: 0, height: -3), elapsed: .milliseconds(20)) == .none)
    }

    @Test
    func dragPastSlopMapsTravelToLevel() {
        var gesture = VolumeGesture(startLevel: 0.5, travel: 100)

        #expect(gesture.move(to: CGSize(width: 0, height: -25), elapsed: .milliseconds(50)) == .level(0.75))
        #expect(gesture.move(to: CGSize(width: 0, height: 100), elapsed: .milliseconds(80)) == .level(0.0))
    }

    @Test
    func aDragThatReturnsInsideTheSlopStaysADrag() {
        var gesture = VolumeGesture(startLevel: 0.5, travel: 100)

        _ = gesture.move(to: CGSize(width: 0, height: -25), elapsed: .milliseconds(50))
        let inside = gesture.move(to: CGSize(width: 0, height: -2), elapsed: .milliseconds(60))
        let outcome = gesture.end(translation: CGSize(width: 0, height: -2), elapsed: .milliseconds(70))

        #expect(inside == .level(0.52))
        #expect(outcome == .level(0.52))
    }

    @Test
    func releaseAfterADragReportsTheFinalLevel() {
        var gesture = VolumeGesture(startLevel: 0.2, travel: 100)

        _ = gesture.move(to: CGSize(width: 0, height: -10), elapsed: .milliseconds(50))
        let outcome = gesture.end(translation: CGSize(width: 0, height: -50), elapsed: .milliseconds(90))

        #expect(outcome == .level(0.7))
    }

    @Test
    func wheelStepsBySixteenthsAndTrackpadIsContinuous() {
        #expect(VolumeGesture.scrolled(0.5, deltaY: 1, isPrecise: false) == 0.5625)
        #expect(VolumeGesture.scrolled(0.5, deltaY: -3, isPrecise: false) == 0.4375)
        #expect(VolumeGesture.scrolled(0.5, deltaY: 20, isPrecise: true) == 0.6)
        #expect(VolumeGesture.scrolled(0.99, deltaY: 1, isPrecise: false) == 1.0)
        #expect(VolumeGesture.scrolled(0.01, deltaY: -40, isPrecise: true) == 0.0)
    }
}
