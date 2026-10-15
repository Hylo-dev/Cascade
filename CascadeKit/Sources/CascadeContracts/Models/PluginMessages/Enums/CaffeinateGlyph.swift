//
//  CaffeinateGlyph.swift
//  CascadeKit
//

/// CaffeinateGlyph is the symbol the user picked to stand for Caffeinate. Raw values are the
/// filled SF Symbol names, the look of a session that is on; the outline twin is the look of one
/// that is off, so the same choice reads as the switch's two states.
public enum CaffeinateGlyph: String, CaseIterable, Sendable {

    case cupHeatWaves = "cup.and.heat.waves.fill"
    case mug          = "mug.fill"
    case pill         = "pill.fill"

    public var filledSymbol: String { rawValue }

    public var outlineSymbol: String {
        switch self {
            case .cupHeatWaves: "cup.and.heat.waves"
            case .mug         : "mug"
            case .pill        : "pill"
        }
    }
}
