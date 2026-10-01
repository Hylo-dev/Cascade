//
//  PluginFont.swift
//  CascadeKit
//

/// PluginFont is a text style or a point size, never both, with an optional weight and design.
/// `monospacedDigit` keeps changing numbers from shifting their neighbours.
public struct PluginFont: Codable, Hashable, Sendable {

    public let style          : PluginTextStyle?
    public let size           : Double?
    public let weight         : PluginFontWeight?
    public let design         : PluginFontDesign?
    public let monospacedDigit: Bool

    public init(
        style          : PluginTextStyle? = nil,
        size           : Double? = nil,
        weight         : PluginFontWeight? = nil,
        design         : PluginFontDesign? = nil,
        monospacedDigit: Bool = false
    ) {
        self.style           = style
        self.size            = size
        self.weight          = weight
        self.design          = design
        self.monospacedDigit = monospacedDigit
    }
}
