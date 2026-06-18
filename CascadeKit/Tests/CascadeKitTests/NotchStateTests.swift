//
//  NotchStateTests.swift
//  CascadeKitTests
//

import Testing
@testable import CascadeKit

/// NotchState is the OptionSet that lets the two sides open independently, so
/// these tests pin down exactly that: closed is empty, open is both, and a
/// single side can move without disturbing the other.
struct NotchStateTests {

    @Test
    func closedIsTheEmptySet() {
        #expect(NotchState.closed.isEmpty)
        #expect(NotchState.closed.isClosed)
    }

    @Test
    func openContainsBothSides() {
        #expect(NotchState.open.contains(.leading))
        #expect(NotchState.open.contains(.trailing))
        #expect(!NotchState.open.isClosed)
    }

    @Test
    func sidesMoveIndependently() {

        var state: NotchState = .leading
        #expect(state.contains(.leading))
        #expect(!state.contains(.trailing))

        state.insert(.trailing)
        #expect(state == .open)

        state.remove(.leading)
        #expect(state == .trailing)
    }

    @Test
    func regionsMapToTheStateThatRevealsThem() {
        #expect(NotchRegion.leading.requiredState  == .leading)
        #expect(NotchRegion.trailing.requiredState == .trailing)
        #expect(NotchRegion.expanded.requiredState == .open)
    }
}
