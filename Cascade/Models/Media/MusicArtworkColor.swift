//
//  MusicArtworkColor.swift
//  Cascade
//

import Foundation

/// MusicArtworkColor keeps sampled sRGB components independent of SwiftUI.
nonisolated struct MusicArtworkColor: Equatable, Sendable {

    let red  : Double
    let green: Double
    let blue : Double

    /// illuminated raises dark colors together, preserving their hue and neutrality.
    var illuminated: Self {
        let brightness = max(red, green, blue)
        let scale      = brightness > 0.02 ? max(1, 0.68 / brightness) : 1

        return Self(
            red  : min(1, red * scale),
            green: min(1, green * scale),
            blue : min(1, blue * scale)
        )
    }

    func distanceSquared(to other: Self) -> Double {
        pow(red - other.red, 2) + pow(green - other.green, 2) + pow(blue - other.blue, 2)
    }
}
