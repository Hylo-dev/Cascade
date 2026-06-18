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
/// It also `ignoresMouseEvents`: the band spans the full width of the screen, so
/// if it intercepted clicks it would swallow the whole top strip. Hover is
/// detected by the global event monitor regardless, so clicks pass straight
/// through everywhere. When widgets need to receive clicks, this will be toggled
/// off only while expanded and only over the live region — not before.
final class NotchPanel: NSPanel {

    init(contentView: NSView) {

        super.init(
            contentRect: contentView.bounds,
            styleMask  : [.borderless, .nonactivatingPanel],
            backing    : .buffered,
            defer      : false
        )

        self.contentView            = contentView
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
