//
//  NotchPanelOrderingTests.swift
//  CascadeKit
//

import AppKit
import Testing
@testable import CascadeKit

/// NotchPanelOrderingTests pin that the overlay's panels appear and disappear at once. With
/// AppKit's default behaviour every order in or out runs a window transform animation on its
/// own dispatch thread; the notch morphs itself and has nothing to gain from it, and where the
/// animation cannot finish, as in a test runner, each one holds its thread for good.
@MainActor
struct NotchPanelOrderingTests {

    @Test
    func theOverlayPanelOrdersWithoutAnAnimation() {
        let panel = NotchPanel(contentView: NSView(frame: CGRect(x: 0, y: 0, width: 440, height: 144)))

        #expect(panel.animationBehavior == .none)
    }

    @Test
    func theFileDropReceiverOrdersWithoutAnAnimation() {
        #expect(NotchFileDropReceiverPanel().animationBehavior == .none)
    }
}
