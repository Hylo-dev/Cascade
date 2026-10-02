//
//  PluginFont+Styles.swift
//  CascadeKit
//

import CascadeContracts

/// PluginFont+Styles gives fonts SwiftUI's spelling: the text styles as static members, so a
/// node reads `.font(.headline)`, a point size through `system(size:weight:design:)`, and
/// `monospacedDigit()` for numbers that must keep their width as they change.
extension PluginFont {

    public static let largeTitle  = PluginFont(style: .largeTitle)
    public static let title       = PluginFont(style: .title)
    public static let title2      = PluginFont(style: .title2)
    public static let title3      = PluginFont(style: .title3)
    public static let headline    = PluginFont(style: .headline)
    public static let subheadline = PluginFont(style: .subheadline)
    public static let body        = PluginFont(style: .body)
    public static let callout     = PluginFont(style: .callout)
    public static let footnote    = PluginFont(style: .footnote)
    public static let caption     = PluginFont(style: .caption)
    public static let caption2    = PluginFont(style: .caption2)

    public static func system(
        size  : Double,
        weight: PluginFontWeight? = nil,
        design: PluginFontDesign? = nil
    ) -> PluginFont {
        PluginFont(size: size, weight: weight, design: design)
    }

    /// monospacedDigit returns the font with digits of one width. It takes a flag, true unless
    /// told otherwise, only because a method with no arguments could not share its name with
    /// the stored `monospacedDigit` property; written `monospacedDigit()`, it reads as SwiftUI's.
    public func monospacedDigit(_ isMonospaced: Bool = true) -> PluginFont {
        PluginFont(
            style          : style,
            size           : size,
            weight         : weight,
            design         : design,
            monospacedDigit: isMonospaced
        )
    }
}
