//
//  SpringTests.swift
//  CascadeKitTests
//

import Testing
@testable import CascadeKit

/// The spring is what makes the morph feel alive *and* what lets it stop: it
/// must converge to its target, settle (so the display link can be torn down),
/// and survive the huge `dt` of a link resuming after the notch sat idle.
struct SpringTests {

    @Test
    func convergesTowardItsTarget() {

        var spring = Spring(parameters: .snappy)

        // Roughly two seconds at 120 Hz is plenty for a snappy spring to settle.
        for _ in 0 ..< 240 {
            spring.advance(toward: 1.0, dt: 1.0 / 120.0)
        }

        #expect(spring.isSettled(at: 1.0))
        #expect(abs(spring.value - 1.0) < 0.01)
    }

    @Test
    func snapJumpsAndKillsVelocity() {

        var spring = Spring(parameters: .snappy)
        spring.advance(toward: 1.0, dt: 1.0 / 120.0)
        spring.snap(to: 0)

        #expect(spring.value == 0)
        #expect(spring.isSettled(at: 0))
    }

    @Test
    func clampsAnEnormousDeltaInsteadOfExploding() {

        var spring = Spring(parameters: .snappy)

        // A five-second dt models the display link resuming after an idle notch.
        spring.advance(toward: 1.0, dt: 5.0)

        #expect(spring.value.isFinite)
        #expect(abs(spring.value) < 10)
    }
}
