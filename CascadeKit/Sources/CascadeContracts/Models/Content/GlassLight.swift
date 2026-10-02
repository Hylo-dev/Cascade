//
//  GlassLight.swift
//  CascadeKit
//

import Foundation

/// GlassLight describes a bounded sRGB light in the expanded notch's coordinate space.
/// Coordinates start at the top left; radius is a fraction of the notch width.
/// Immutable, validated values keep malformed plugin input out of the renderer.
public struct GlassLight: Codable, Equatable, Sendable {

    public static let maximumCount = 8

    public let x        : Double
    public let y        : Double
    public let radius   : Double
    public let red      : Double
    public let green    : Double
    public let blue     : Double
    public let intensity: Double

    public init(
        x        : Double,
        y        : Double,
        radius   : Double,
        red      : Double,
        green    : Double,
        blue     : Double,
        intensity: Double
    ) throws {
        try ContractValidation.require(
            [x, y, radius, red, green, blue, intensity].allSatisfy {
                $0.isFinite && (0...1).contains($0)
            } && radius > 0,
            "Invalid glass light"
        )

        self.x         = x
        self.y         = y
        self.radius    = radius
        self.red       = red
        self.green     = green
        self.blue      = blue
        self.intensity = intensity
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            x        : container.decode(Double.self, forKey: .x),
            y        : container.decode(Double.self, forKey: .y),
            radius   : container.decode(Double.self, forKey: .radius),
            red      : container.decode(Double.self, forKey: .red),
            green    : container.decode(Double.self, forKey: .green),
            blue     : container.decode(Double.self, forKey: .blue),
            intensity: container.decode(Double.self, forKey: .intensity)
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case x, y, radius, red, green, blue, intensity
    }
}
