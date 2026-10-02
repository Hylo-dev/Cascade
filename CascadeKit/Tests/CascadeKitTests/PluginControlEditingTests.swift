//
//  PluginControlEditingTests.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import Observation
import SwiftUI
import Testing
@testable import CascadeKit
@testable import CascadePluginEngine

/// PluginControlEditingTests press the renderer's controls in an off-screen window, with the
/// pointer's own events, while the widget board edits and while it does not. A press on an
/// editing board moves the widget, so a control must send nothing then, even one whose press
/// began before the board started editing, which is what a long press on a button does.
@MainActor
struct PluginControlEditingTests {

    /// Board stands in for the widget board: whether it edits, which a tile hands its widget
    /// through the environment, and the actions the store sent.
    @Observable
    final class Board {

        var isEditing = false

        @ObservationIgnored
        var sent: [PluginActionRequest] = []
    }

    /// Tile draws a publication with the board's editing flag, as a widget tile does.
    private struct Tile: View {

        let store: PluginNodeStore
        let board: Board

        var body: some View {
            PluginDocumentView(store: store)
                .frame(width: 200, height: 40)
                .environment(\.isEditingWidgets, board.isEditing)
        }
    }

    /// Surface is one control drawn in a window far off screen, which takes the events a test
    /// sends it as it would the pointer's.
    @MainActor
    private final class Surface {

        let board : Board
        let store : PluginNodeStore
        let window: NSWindow

        init(_ node: PluginNode) throws {
            var publisher = PluginRenderFixtures.Publisher()
            let board     = Board()
            self.board    = board
            store         = PluginNodeStore(
                key     : PluginRenderFixtures.key,
                submit  : { board.sent.append($0) },
                schedule: { _, _ in }
            )
            store.apply(publisher.publish(try PluginDocument(root: node)))

            window = NSWindow(
                contentRect: CGRect(x: -10_000, y: -10_000, width: 200, height: 40),
                styleMask  : .borderless,
                backing    : .buffered,
                defer      : false
            )
            window.isReleasedWhenClosed = false
            window.contentView          = NSHostingView(rootView: Tile(store: store, board: board))
            window.orderFront(nil)
        }

        /// setEditing changes the board's flag and lets SwiftUI draw the change.
        func setEditing(_ isEditing: Bool) async throws {
            board.isEditing = isEditing
            try await Task.sleep(for: .milliseconds(50))
        }

        /// click presses the middle of the window and lets go, running `meanwhile` while the
        /// button is held down.
        func click(meanwhile: () async throws -> Void = {}) async throws {
            try await Task.sleep(for: .milliseconds(50))
            window.sendEvent(mouse(.leftMouseDown))
            try await Task.sleep(for: .milliseconds(50))
            try await meanwhile()
            window.sendEvent(mouse(.leftMouseUp))
            try await Task.sleep(for: .milliseconds(50))
        }

        /// slide moves the slider to `value` as one drag and its release: the slider's own action,
        /// sent outside a mouse loop, makes SwiftUI begin the drag, set the value and end it.
        func slide(to value: Double) async throws {
            try await Task.sleep(for: .milliseconds(50))
            let slider = try #require(views(in: window.contentView).lazy.compactMap { $0 as? NSSlider }.first)
            slider.doubleValue = value
            _ = slider.sendAction(slider.action, to: slider.target)
            try await Task.sleep(for: .milliseconds(50))
        }

        func close() {
            window.orderOut(nil)
            window.close()
        }

        private func mouse(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(
                with         : type,
                location     : CGPoint(x: 100, y: 20),
                modifierFlags: [],
                timestamp    : ProcessInfo.processInfo.systemUptime,
                windowNumber : window.windowNumber,
                context      : nil,
                eventNumber  : 0,
                clickCount   : 1,
                pressure     : type == .leftMouseDown ? 1 : 0
            ) ?? NSEvent()
        }

        private func views(in view: NSView?) -> [NSView] {
            guard let view else { return [] }

            return [view] + view.subviews.flatMap { views(in: $0) }
        }
    }

    @Test
    func aButtonSendsNothingWhileTheBoardIsEditingNorWhenEditingBeginsDuringItsPress() async throws {
        let surface = try Surface(PluginNode(.button(action: "next"), id: "next", children: [PluginNode(.text("WWWWWWWWWW"))]))
        defer { surface.close() }

        try await surface.click()
        #expect(surface.board.sent.map(\.node) == [PluginNodeID(rawValue: "#next:button")])

        try await surface.setEditing(true)
        try await surface.click()
        #expect(surface.board.sent.count == 1, "A press on an editing board moves the widget")

        try await surface.setEditing(false)
        try await surface.click { try await surface.setEditing(true) }
        #expect(surface.board.sent.count == 1, "A long press that started editing is not a click")
    }

    @Test
    func aToggleSendsNothingWhileTheBoardIsEditingNorWhenEditingBeginsDuringItsPress() async throws {
        let surface = try Surface(PluginNode(.toggle(isOn: false, action: "mute"), id: "mute", children: [PluginNode(.text("WWWWWWWWWW"))]))
        defer { surface.close() }

        try await surface.click()
        #expect(surface.board.sent.map(\.value) == [.bool(true)])

        try await surface.setEditing(true)
        try await surface.click()
        try await surface.setEditing(false)
        try await surface.click { try await surface.setEditing(true) }

        #expect(surface.board.sent.count == 1)
    }

    @Test
    func aSliderSendsNothingWhileTheBoardIsEditingAndADragEditingInterruptedGoesBack() async throws {
        let surface = try Surface(PluginNode(.slider(value: 0, minimum: 0, maximum: 1, step: nil, action: "seek"), id: "seek"))
        let model   = try #require(surface.store.model(PluginNodeID(rawValue: "#seek:slider")))
        defer { surface.close() }

        try await surface.slide(to: 0.7)
        #expect(surface.board.sent.map(\.value) == [.number(0.7)])

        try await surface.setEditing(true)
        try await surface.slide(to: 0.4)
        #expect(surface.board.sent.count == 1)

        try await surface.setEditing(false)
        surface.store.drag(0.2, on: model)
        try await surface.setEditing(true)
        try await surface.slide(to: 0.9)

        #expect(surface.board.sent.count == 1, "A drag the board's editing interrupted sends nothing")
        #expect(!model.isDragging && model.optimistic == nil, "Its thumb goes back to the published value")
    }
}
