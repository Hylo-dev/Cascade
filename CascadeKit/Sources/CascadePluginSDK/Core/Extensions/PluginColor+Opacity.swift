//
//  PluginColor+Opacity.swift
//  CascadeKit
//

import CascadeContracts

extension PluginColor {

    /// opacity(_:) returns the color with its opacity multiplied by `opacity`, as SwiftUI's
    /// `Color.opacity(_:)` does, so `.white.opacity(0.55)` is a dimmed white.
    public func opacity(_ opacity: Double) -> PluginColor {
        PluginColor(
            red    : red,
            green  : green,
            blue   : blue,
            opacity: self.opacity * opacity
        )
    }
}
