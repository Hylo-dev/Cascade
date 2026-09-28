//
//  FileShelfGlassLightEmitter.swift
//  Cascade
//

import AppKit
import CascadeContracts
import CascadePresentation
import SwiftUI

struct FileShelfGlassLightEmitter: View {

    let isOccupied : Bool
    let isHovering : Bool
    let isAdmitting: Bool

    var body: some View {
        Color.clear
            .notchGlassLights(lights)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var lights: [GlassLight] {
        guard isOccupied || isHovering else { return [] }

        let intensity = isAdmitting ? 0.52 : isHovering ? 0.38 : 0.22
        return [
            try? GlassLight(
                x        : 0.18,
                y        : 0.28,
                radius   : 0.34,
                red      : 0.24,
                green    : 0.56,
                blue     : 1,
                intensity: intensity
            ),
            try? GlassLight(
                x        : 0.82,
                y        : 0.36,
                radius   : 0.28,
                red      : 0.27,
                green    : 0.82,
                blue     : 0.95,
                intensity: intensity * 0.7
            ),
        ].compactMap(\.self)
    }
}
