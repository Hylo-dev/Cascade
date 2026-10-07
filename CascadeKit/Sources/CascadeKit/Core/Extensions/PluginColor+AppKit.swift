//
//  PluginColor+AppKit.swift
//  CascadeKit
//

import AppKit
import CascadeContracts

extension PluginColor {

    /// nsColor is the same sRGB color for the views that draw with AppKit, such as the rolling
    /// digits of a time node.
    var nsColor: NSColor {
        NSColor(
            srgbRed: red,
            green  : green,
            blue   : blue,
            alpha  : opacity
        )
    }
}
