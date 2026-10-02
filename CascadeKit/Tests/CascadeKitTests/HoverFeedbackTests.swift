//
//  HoverFeedbackTests.swift
//  CascadeKit
//

import Testing
@testable import CascadeKit

@MainActor
struct HoverFeedbackTests {

    @Test
    func performsImmediatelyOncePerHoverEntry() {
        let performer = HapticFixture()
        let feedback  = HoverFeedback(performer: performer)

        feedback.update(isHovering: true)
        #expect(performer.impulses == 1)

        feedback.update(isHovering: true)
        #expect(performer.impulses == 1)

        feedback.update(isHovering: false)
        feedback.update(isHovering: true)
        #expect(performer.impulses == 2)
    }

    @Test
    func enablingDuringAnExistingHoverDoesNotEmitDelayedFeedback() {
        let performer = HapticFixture()
        let feedback  = HoverFeedback(performer: performer)

        feedback.isEnabled = false
        feedback.update(isHovering: true)
        feedback.isEnabled = true
        feedback.update(isHovering: true)
        #expect(performer.impulses == 0)
    }

    @Test
    func aSnapTicksOnlyWhileHapticsAreOn() {
        let performer = HapticFixture()
        let feedback  = HoverFeedback(performer: performer)

        feedback.snap()
        feedback.isEnabled = false
        feedback.snap()

        #expect(performer.impulses == 1)
    }
}
