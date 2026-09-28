//
//  NotchPanel.swift
//  CascadeKit
//

import AppKit

/// NotchPanel is the always-on overlay window.
///
/// It is a borderless, nonactivating `NSPanel` so it never steals focus from
/// the app the user is actually working in. Its collection behavior is what
/// makes it persist across every Space and survive full-screen transitions, and
/// its window level sits above the menu bar so the chrome can sit flush in the
/// notch region. The panel never becomes key or main.
///
/// The controller toggles `ignoresMouseEvents` from the exact animated path
/// under the cursor. This matters because the panel's frame spans the whole menu
/// bar and AppKit cannot pass a click to another process using view hit-testing
/// alone.
final class NotchPanel: NSPanel {

    init(contentView: NSView) {

        super.init(
            contentRect: contentView.bounds,
            styleMask  : [.borderless, .nonactivatingPanel],
            backing    : .buffered,
            defer      : false
        )

        // The content canvas keeps its original coordinates above a transparent
        // bottom gutter. A separate root lets its halo extend outside the canvas
        // while remaining inside the window, without changing hit-test geometry.
        let rootView = NSView(frame: contentView.bounds)
        rootView.wantsLayer = true
        rootView.clipsToBounds = false
        rootView.addSubview(contentView)
        self.contentView            = rootView
        isFloatingPanel             = true
        isOpaque                    = false
        backgroundColor             = .clear
        hasShadow                   = false
        level                       = .statusBar
        ignoresMouseEvents          = true
        hidesOnDeactivate           = false
        isMovableByWindowBackground = false
        collectionBehavior          = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    }

    // A borderless panel refuses key/main by default; we state it explicitly so
    // no future change can accidentally let the overlay grab focus.
    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
