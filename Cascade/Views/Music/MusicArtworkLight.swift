//
//  MusicArtworkLight.swift
//  Cascade
//

import AppKit
import SwiftUI

/// MusicArtworkLight shows the compact cover's glow, drawn once per cover by
/// MusicArtworkDecoder.compactGlow. The compact notch is solid black, with no
/// glass to light.
struct MusicArtworkLight: View {

    let visual     : MusicVisualState
    let artworkSize: CGFloat

    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency

    var body: some View {
        if let glow = visual.compactGlow, visual.artwork != nil, !reduceTransparency {
            let lightSize = artworkSize * MusicArtworkDecoder.compactGlowSize / MusicArtworkDecoder.compactArtworkSize

            Image(nsImage: glow)
                .resizable()
                .frame(width: lightSize, height: lightSize)
                .opacity(0.18)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}
