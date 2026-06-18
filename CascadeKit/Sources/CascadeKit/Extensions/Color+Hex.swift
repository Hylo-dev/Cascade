//
//  Color+Hex.swift
//  CascadeKit
//

import SwiftUI

/// Color + hex / ARGB construction.
///
/// Lets the configuration (and widget authors) write colors the way they think
/// about them — `Color(hex: 0xFF3B30)` or `Color(argb: 0xFFFF3B30)` — instead of
/// spelling out four `Double` components. Both build in the sRGB space, which
/// is what the notch chrome and content are composited in.
public extension Color {

    /// Build an opaque color from a packed RGB hex, `0xRRGGBB`.
    /// `opacity` overrides the alpha if you want translucency.
    init(
        hex    : UInt32,
        opacity: Double = 1
    ) {
        let red   = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >>  8) & 0xFF) / 255.0
        let blue  = Double( hex        & 0xFF) / 255.0

        self.init(
            .sRGB,
            red    : red,
            green  : green,
            blue   : blue,
            opacity: opacity
        )
    }

    /// Build a color from a packed ARGB value, `0xAARRGGBB` (alpha in the top
    /// byte). Matches the layout the renderer used before colors became `Color`.
    init(argb: UInt32) {
        let alpha = Double((argb >> 24) & 0xFF) / 255.0
        let red   = Double((argb >> 16) & 0xFF) / 255.0
        let green = Double((argb >>  8) & 0xFF) / 255.0
        let blue  = Double( argb        & 0xFF) / 255.0

        self.init(
            .sRGB,
            red    : red,
            green  : green,
            blue   : blue,
            opacity: alpha
        )
    }
}
