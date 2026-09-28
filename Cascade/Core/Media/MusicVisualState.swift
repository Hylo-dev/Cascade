//
//  MusicVisualState.swift
//  Cascade
//

import AppKit
import CascadeKit
import CoreImage
import Observation
import QuartzCore
import SwiftUI

/// MusicVisualState shares a cover palette between the static light and PCM bars.
@MainActor
@Observable
final class MusicVisualState {
    var artwork: NSImage?
    var compactGlow: NSImage?
    var bands = AudioSpectrumFrame.silence.bands
    var palette: [Color] = [.gray, .gray]
    var artworkColors: [MusicArtworkColor] = []
}
