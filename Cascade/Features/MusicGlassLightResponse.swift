import Foundation

/// Uses the existing measured 40–180 Hz and 180–500 Hz envelopes. No clock or
/// generated rhythm: missing/silent PCM leaves only a steady artwork wash.
nonisolated struct MusicGlassLightResponse: Equatable {
    let intensity: Double
    let radius: Double

    init(bands: [Float], isPlaying: Bool, reducesMotion: Bool) {
        func energy(_ index: Int) -> Double {
            guard bands.indices.contains(index), bands[index].isFinite else { return 0 }
            return min(1, max(0, Double(bands[index])))
        }
        let bass = isPlaying && !reducesMotion
            ? pow(energy(0) * 0.8 + energy(1) * 0.2, 1.6) : 0
        intensity = (isPlaying ? 0.32 : 0.16) + 0.58 * bass
        radius = 0.48 + 0.22 * bass
    }
}
