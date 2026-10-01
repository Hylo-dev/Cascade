//
//  WidgetEditingKeyboardTarget.swift
//  CascadeKit
//

import AppKit
import SwiftUI

/// WidgetEditingKeyboardTarget lets Escape end widget editing. The notch panel never takes the
/// keyboard on its own, so while editing this zero-size native view becomes its first responder
/// and makes it key, which a nonactivating panel does without activating Cascade; it gives the
/// keyboard back when editing ends and the view leaves the window. Every other key is swallowed
/// while editing, so typing does not beep.
struct WidgetEditingKeyboardTarget: NSViewRepresentable {

    let onEscape: () -> Void

    func makeNSView(context: Context) -> KeyView {
        let view      = KeyView(frame: .zero)
        view.onEscape = onEscape
        return view
    }

    func updateNSView(
        _ view : KeyView,
        context: Context
    ) {
        view.onEscape = onEscape
    }

    /// KeyView is the native responder behind the target.
    final class KeyView: NSView, NotchKeyboardFocusTarget {

        var onEscape: () -> Void = {}

        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }

            window.makeFirstResponder(self)
            window.makeKey()
        }

        override func keyDown(with event: NSEvent) {
            if event.keyCode == 53 { onEscape() }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, let window, window.firstResponder === self, window.isKeyWindow {
                window.resignKey()
            }
            super.viewWillMove(toWindow: newWindow)
        }
    }
}
