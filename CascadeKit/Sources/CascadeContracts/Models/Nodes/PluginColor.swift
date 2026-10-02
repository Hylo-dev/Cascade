//
//  PluginColor.swift
//  CascadeKit
//

/// PluginColor is an sRGB color with opacity, every component from 0 to 1.
public struct PluginColor: Codable, Hashable, Sendable {

    public static let white = PluginColor(red: 1, green: 1, blue: 1)
    public static let black = PluginColor(red: 0, green: 0, blue: 0)

    public let red    : Double
    public let green  : Double
    public let blue   : Double
    public let opacity: Double

    public init(
        red    : Double,
        green  : Double,
        blue   : Double,
        opacity: Double = 1
    ) {
        self.red     = red
        self.green   = green
        self.blue    = blue
        self.opacity = opacity
    }
}
