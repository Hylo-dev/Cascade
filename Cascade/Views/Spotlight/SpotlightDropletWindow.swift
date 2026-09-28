//
//  SpotlightDropletWindow.swift
//  Cascade
//

import AppKit

/// SpotlightDropletWindow presents a mouse-transparent surface without stealing keyboard focus.
///
/// Level 24 places the handoff above native Spotlight's field and below Cascade's
/// notch. The window covers only the path from the notch to the landed capsule.
@MainActor
final class SpotlightDropletWindow: NSPanel {

    init(frame: CGRect) {
        super.init(
            contentRect : frame,
            styleMask   : [.borderless, .nonactivatingPanel],
            backing     : .buffered,
            defer       : false
        )

        level                       = NSWindow.Level(rawValue: 24)
        backgroundColor             = .clear
        isOpaque                    = false
        hasShadow                   = false
        ignoresMouseEvents          = true
        hidesOnDeactivate           = false
        isReleasedWhenClosed        = false
        animationBehavior           = .none
        collectionBehavior          = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isExcludedFromWindowsMenu   = true
        isMovable                   = false
        setAccessibilityElement(false)
    }

    override var canBecomeKey: Bool {
        false
    }

    override var canBecomeMain: Bool {
        false
    }
}
