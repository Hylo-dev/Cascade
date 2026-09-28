//
//  MusicArtwork.swift
//  Cascade
//

import AppKit
import CascadeKit
import CoreImage
import Observation
import QuartzCore
import SwiftUI

struct MusicArtwork: View {
    let visual: MusicVisualState
    let size: CGFloat
    var isCompact = false
    var isPlaying = true
    var isStale = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            // A paused cover keeps its colors; only its size and light respond.
            // Each cover is its own identity, so a new one blurs in over the
            // outgoing one instead of replacing it in a single frame.
            if let artwork = visual.artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
                    .id(ObjectIdentifier(artwork))
                    .transition(MusicTrackTransition.cover(reduceMotion: reduceMotion))
            } else {
                RoundedRectangle(cornerRadius: size * 0.2).fill(.white.opacity(0.10))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: size * 0.45, weight: .regular))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .transition(MusicTrackTransition.cover(reduceMotion: reduceMotion))
            }
        }
        .animation(MusicTrackTransition.animation(reduceMotion: reduceMotion), value: visual.artwork.map(ObjectIdentifier.init))
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
        .background {
            if isCompact {
                MusicArtworkLight(visual: visual, artworkSize: size)
                    .opacity(isPlaying ? 1 : 0)
            } else {
                // The expanded cover lights the glass beneath the content
                // rather than painting a glow over it.
                MusicGlassLightEmitter(visual: visual, isPlaying: isPlaying && !isStale)
            }
        }
        .scaleEffect(isPlaying ? 1 : 0.92)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: isPlaying)
        .accessibilityHidden(true)
    }
}
