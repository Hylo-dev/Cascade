//
//  WidgetPressTests.swift
//  CascadeKit
//

import CoreGraphics
import Testing
@testable import CascadeKit

struct WidgetPressTests {

    @Test
    func aStillPressCanStartEditingAndAMovedOneCannot() {
        var still = WidgetPress(isEditing: false)
        var moved = WidgetPress(isEditing: false)

        still.move(to: CGSize(width: 2, height: 1))
        moved.move(to: CGSize(width: 12, height: 0))

        #expect(still.canStartEditing)
        #expect(!moved.canStartEditing)
        #expect(still.offset == nil)
    }

    @Test
    func thePressThatStartedEditingMovesTheWidgetFromThere() {
        var press = WidgetPress(isEditing: false)
        press.move(to: CGSize(width: 2, height: 1))

        press.beginEditing()
        press.move(to: CGSize(width: 32, height: 11))

        #expect(press.offset == CGSize(width: 30, height: 10))
        #expect(!press.canStartEditing)
    }

    @Test
    func aPressWhileEditingFollowsAtOnce() {
        var press = WidgetPress(isEditing: true)

        press.move(to: CGSize(width: 15, height: -4))

        #expect(press.offset == CGSize(width: 15, height: -4))
        #expect(!press.canStartEditing)
    }
}
