//
//  MusicGlassLightEmitter.swift
//  Cascade
//

import AppKit
import SwiftUI

/// MusicGlassLightEmitter lights the notch's glass from the cover. It sits
/// behind the artwork, so the light rises from where the cover is, and hands
/// its lights straight to the glass through NotchGlassLightReceiving: the
/// spectrum modulates them 30 times a second, and through a SwiftUI preference
/// every tick re-evaluated the view tree (measured ~1.3 % of a core more). The
/// glass lies above the light, so it smokes and bends it like anything behind.
struct MusicGlassLightEmitter: NSViewRepresentable {

    let visual   : MusicVisualState
    let isPlaying: Bool

    @Environment(\.accessibilityReduceMotion)
    private var reducesMotion
    @Environment(\.accessibilityReduceTransparency)
    private var reducesTransparency

    func makeNSView(context: Context) -> MusicGlassLightView {
        MusicGlassLightView(visual: visual)
    }

    func updateNSView(
        _ view : MusicGlassLightView,
        context: Context
    ) {
        view.configure(
            isPlaying    : isPlaying,
            reducesMotion: reducesMotion,
            isEnabled    : !reducesTransparency
        )
    }

    static func dismantleNSView(
        _ view     : MusicGlassLightView,
        coordinator: ()
    ) {
        view.withdraw()
    }
}
