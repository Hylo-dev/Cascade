//
//  KeyboardTarget.swift
//  CascadeKit
//

import AppKit
import Testing
@testable import CascadeKit

@MainActor
final class KeyboardTarget: NSView, NotchKeyboardFocusTarget {

    override var acceptsFirstResponder: Bool { true }
}
