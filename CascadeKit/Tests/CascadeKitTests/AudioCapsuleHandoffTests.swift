//
//  AudioCapsuleHandoffTests.swift
//  CascadeKit
//

import CoreGraphics
import Testing
@testable import CascadeKit

@MainActor
struct AudioCapsuleHandoffTests {

    /// Clock is a hand-moved clock, so freshness is tested without waiting.
    final class Clock {

        var now = ContinuousClock.now
    }

    private let widgetFrame = CGRect(x: 541, y: 42, width: 39, height: 83)
    private let mixerFrame  = CGRect(x: 547, y: 37, width: 39, height: 83)

    @Test
    func aCapsuleWithNothingBeforeItStartsInPlace() {
        let handoff = AudioCapsuleHandoff()

        #expect(handoff.origin(for: .mixer) == nil)
    }

    @Test
    func theMixerStartsWhereTheWidgetWasWhileTheSwapIsUnderway() {
        let handoff = AudioCapsuleHandoff()
        handoff.record(widgetFrame, for: .widget)

        #expect(handoff.origin(for: .mixer) == widgetFrame)
    }

    @Test
    func theWidgetStartsWhereTheMixerLeftAMomentAgo() {
        let clock   = Clock()
        let handoff = AudioCapsuleHandoff(now: { clock.now })
        handoff.record(mixerFrame, for: .mixer)
        handoff.leave(.mixer)
        clock.now += .milliseconds(200)

        #expect(handoff.origin(for: .widget) == mixerFrame)
    }

    @Test
    func aCapsuleThatLeftLongAgoIsNotGlidedFrom() {
        let clock   = Clock()
        let handoff = AudioCapsuleHandoff(now: { clock.now })
        handoff.record(mixerFrame, for: .mixer)
        handoff.leave(.mixer)
        clock.now += .seconds(2)

        #expect(handoff.origin(for: .widget) == nil)
    }

    @Test
    func aSightingGlidesOnce() {
        let handoff = AudioCapsuleHandoff()
        handoff.record(widgetFrame, for: .widget)

        #expect(handoff.origin(for: .mixer) == widgetFrame)
        #expect(handoff.origin(for: .mixer) == nil)
    }

    @Test
    func aCapsuleNeverGlidesFromItself() {
        let handoff = AudioCapsuleHandoff()
        handoff.record(widgetFrame, for: .widget)

        #expect(handoff.origin(for: .widget) == nil)
    }

    @Test
    func theMixerKnowsItIsArrivingBeforeAndAfterTheCapsuleTakesTheSighting() {
        let handoff = AudioCapsuleHandoff()
        #expect(!handoff.isArriving(.mixer))

        handoff.record(widgetFrame, for: .widget)
        #expect(handoff.isArriving(.mixer))

        _ = handoff.origin(for: .mixer)
        #expect(handoff.isArriving(.mixer))
        #expect(!handoff.isArriving(.widget))
    }

    @Test
    func anArrivalIsForgottenOnceItIsStale() {
        let clock   = Clock()
        let handoff = AudioCapsuleHandoff(now: { clock.now })
        handoff.record(widgetFrame, for: .widget)
        _ = handoff.origin(for: .mixer)
        clock.now += .seconds(2)

        #expect(!handoff.isArriving(.mixer))
    }

    @Test
    func thePillIsCentredInTheControlWithTheCapsulesProportions() {
        let pill = AudioGlobalVolumeControl.pillFrame(
            in        : CGRect(x: 100, y: 0, width: 80, height: 83),
            widthRatio: 0.6
        )

        #expect(abs(pill.width - 83 * AudioVolumeCapsuleMetrics.aspect) < 0.001)
        #expect(abs(pill.height - 83) < 0.001)
        #expect(abs(pill.midX - 140) < 0.001)
    }
}
