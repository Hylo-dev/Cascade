//
//  NotchControllerWidgetEditingTests.swift
//  CascadeKit
//

import AppKit
import Testing
@testable import CascadeKit

/// NotchControllerWidgetEditingTests covers what editing changes about the surface: the notch
/// stays open while the pointer wanders, grows to make room for the gallery, and editing ends
/// with a click outside the notch, with any collapse, and when the notch is hidden.
@MainActor
struct NotchControllerWidgetEditingTests {

    private let inside  = CGPoint(x: 500, y: 790)
    private let outside = CGPoint(x: 50, y: 400)

    private func openFixture() -> ControllerFixture {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.register(ControllerWidgetFixture())
        fixture.controller.start()
        fixture.monitor.sendPointer(inside)

        return fixture
    }

    @Test
    func editingKeepsTheNotchOpenUntilItEnds() {
        let fixture = openFixture()
        defer { fixture.controller.stop() }

        fixture.controller.surface.setWidgetEditing(true)
        fixture.monitor.sendPointer(outside)

        #expect(fixture.controller.state == .open)

        fixture.controller.surface.setWidgetEditing(false)

        #expect(fixture.controller.state == .closed)
    }

    @Test
    func editingGrowsTheNotchForTheGallery() throws {
        let fixture = openFixture()
        defer { fixture.controller.stop() }
        let resting = try #require(fixture.controller.expandedFrame)

        fixture.controller.surface.setWidgetEditing(true)

        let editing = try #require(fixture.controller.expandedFrame)
        #expect(editing.height == resting.height + NotchController.widgetGalleryHeight)
        #expect(editing.maxY == resting.maxY)
    }

    @Test
    func aClickInsideTheNotchKeepsEditing() {
        let fixture = openFixture()
        defer { fixture.controller.stop() }
        fixture.controller.surface.setWidgetEditing(true)

        fixture.monitor.sendButton(isPressed: true)

        #expect(fixture.controller.surface.isEditingWidgets)
    }

    @Test
    func aClickOutsideTheNotchEndsEditingAndClosesIt() {
        let fixture = openFixture()
        defer { fixture.controller.stop() }
        fixture.controller.surface.setWidgetEditing(true)
        fixture.monitor.sendPointer(outside)

        fixture.monitor.sendButton(isPressed: true)

        #expect(!fixture.controller.surface.isEditingWidgets)
        #expect(fixture.controller.state == .closed)
    }

    @Test
    func lockingTheScreenEndsEditing() {
        let fixture = openFixture()
        defer { fixture.controller.stop() }
        fixture.controller.surface.setWidgetEditing(true)

        fixture.monitor.sendLock()

        #expect(!fixture.controller.surface.isEditingWidgets)
    }

    @Test
    func editingCannotBeginWhileTheNotchIsClosed() {
        let fixture = ControllerFixture(reducesMotion: true)
        fixture.controller.register(ControllerWidgetFixture())
        fixture.controller.start()
        defer { fixture.controller.stop() }

        fixture.controller.surface.setWidgetEditing(true)

        #expect(!fixture.controller.surface.isEditingWidgets)
    }
}
