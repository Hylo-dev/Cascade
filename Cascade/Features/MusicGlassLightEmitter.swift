import CascadeContracts
import CascadePresentation
import SwiftUI

/// This tiny view observes spectrum changes; playback controls and metadata do
/// not rebuild for light frames. It uses exactly the same public SDK preference
/// as other modules and is installed only in the expanded music surface.
struct MusicGlassLightEmitter: View {
    let visual: MusicVisualState
    let isPlaying: Bool
    @Environment(\.accessibilityReduceMotion) private var reducesMotion

    var body: some View {
        Color.clear
            .notchGlassLights(lights)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var lights: [GlassLight] {
        guard visual.artwork != nil, !visual.artworkColors.isEmpty else { return [] }
        let response = MusicGlassLightResponse(
            bands: visual.bands, isPlaying: isPlaying, reducesMotion: reducesMotion
        )
        // The first source sits beside the cover, the second carries its other
        // sampled hue into the lower glass. Positions are notch-normalized.
        return visual.artworkColors.prefix(2).enumerated().compactMap { index, color in
            try? GlassLight(
                x: index == 0 ? 0.18 : 0.64,
                y: index == 0 ? 0.55 : 0.92,
                radius: response.radius,
                red: color.red, green: color.green, blue: color.blue,
                intensity: response.intensity * (index == 0 ? 1 : 0.7)
            )
        }
    }
}
