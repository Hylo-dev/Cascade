//
//  MusicVisualState.swift
//  Cascade
//

import AppKit
import Observation
import SwiftUI

/// MusicVisualState shares a cover palette between the static light and PCM bars.
@MainActor
@Observable
final class MusicVisualState {

    var artwork      : NSImage?
    var compactGlow  : NSImage?
    var bands         = AudioSpectrumFrame.silence.bands
    var palette      : [Color] = [.gray, .gray]
    var artworkColors: [MusicArtworkColor] = []
}
