//
//  OptionsBackButton.swift
//  CascadeKit
//

import AppKit

/// OptionsBackButton permits keyboard focus in the nonactivating notch panel.
/// It inherits the same native hover and pressed feedback as the settings button.
final class OptionsBackButton: NSButton, NotchKeyboardFocusTarget {

    override var acceptsFirstResponder: Bool { true }
}
