//
//  ScrollWheelReaderTests.swift
//  CascadeKit
//

import Testing
@testable import CascadeKit

struct ScrollWheelReaderTests {

    @Test
    func aDeviceThatReportsTheFingersKeepsItsSign() {
        #expect(ScrollWheelReader.physicalDeltaY(12, isDirectionInverted: false) == 12)
        #expect(ScrollWheelReader.physicalDeltaY(-12, isDirectionInverted: false) == -12)
    }

    @Test
    func naturalScrollingIsUndoneSoUpwardStaysPositive() {
        #expect(ScrollWheelReader.physicalDeltaY(-12, isDirectionInverted: true) == 12)
        #expect(ScrollWheelReader.physicalDeltaY(12, isDirectionInverted: true) == -12)
    }

    @Test
    func noMovementStaysNoMovement() {
        #expect(ScrollWheelReader.physicalDeltaY(0, isDirectionInverted: true) == 0)
        #expect(ScrollWheelReader.physicalDeltaY(0, isDirectionInverted: false) == 0)
    }
}
