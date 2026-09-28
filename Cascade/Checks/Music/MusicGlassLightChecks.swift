//
//  MusicGlassLightChecks.swift
//  Cascade
//

#if MUSIC_GLASS_LIGHT_TESTS
import Foundation

@main
struct MusicGlassLightChecks {
    static func main() {
        let quiet = MusicGlassLightResponse(bands: [0, 0, 0, 0, 0, 0], isPlaying: true, reducesMotion: false)
        let bass = MusicGlassLightResponse(bands: [1, 0.8, 0, 0, 0, 0], isPlaying: true, reducesMotion: false)
        let treble = MusicGlassLightResponse(bands: [0, 0, 0, 0, 1, 1], isPlaying: true, reducesMotion: false)
        precondition(bass.intensity > quiet.intensity && bass.radius > quiet.radius)
        precondition(treble == quiet, "High frequencies must not invent a bass glow")
        let reduced = MusicGlassLightResponse(bands: [1, 1], isPlaying: true, reducesMotion: true)
        precondition(reduced == quiet, "Reduced motion keeps only ambient artwork light")
        let paused = MusicGlassLightResponse(bands: [1, 1], isPlaying: false, reducesMotion: false)
        let pausedQuiet = MusicGlassLightResponse(bands: [], isPlaying: false, reducesMotion: false)
        precondition(paused == pausedQuiet && paused.intensity < quiet.intensity)
        let invalid = MusicGlassLightResponse(bands: [.nan, .infinity], isPlaying: true, reducesMotion: false)
        precondition(invalid == quiet)
        let loud = MusicGlassLightResponse(bands: [10, 10], isPlaying: true, reducesMotion: false)
        precondition(loud.intensity <= 1 && loud.radius <= 1)
        precondition(quiet.intensity > 0, "Silence retains static cover color without a beat")
        print("Music glass lighting: 7 behavior checks passed")
    }
}

#endif
