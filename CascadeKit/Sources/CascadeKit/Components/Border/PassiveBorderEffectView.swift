//
//  PassiveBorderEffectView.swift
//  CascadeKit
//

import AppKit

/// PassiveBorderEffectView is the decorative surface; it must never take clicks
/// from notch controls.
@MainActor
final class PassiveBorderEffectView: NSVisualEffectView {

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
