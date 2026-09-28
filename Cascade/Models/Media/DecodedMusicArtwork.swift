//
//  DecodedMusicArtwork.swift
//  Cascade
//

import CoreGraphics

/// DecodedMusicArtwork transfers an immutable CGImage and a small palette from
/// the decoder worker. No NSImage or SwiftUI objects cross that actor boundary.
nonisolated struct DecodedMusicArtwork: @unchecked Sendable {

    let image : CGImage
    let colors: [MusicArtworkColor]
    /// The compact cover's glow, drawn once here; see `compactGlow`.
    let glow  : CGImage?
}
