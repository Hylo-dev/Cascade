//
//  OptionsBackButton.swift
//  CascadeKit
//

import AppKit

/// OptionsBackButton keeps native click feedback without becoming a keyboard target.
/// Navigation chrome must never display a selection or focus ring.
final class OptionsBackButton: NSButton {

    override var acceptsFirstResponder: Bool { false }
}

/// OptionsKeyboardTarget receives Escape in the nonactivating panel without
/// selecting a visible control. Its lifetime is bounded by its owning host. Every
/// other key is swallowed while the page holds the keyboard, so typing does not beep.
final class OptionsKeyboardTarget: NSResponder, NotchKeyboardFocusTarget {

    var onEscape: @MainActor () -> Void = {}

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape() }
    }
}
