//
//  AudioVolumeGlassLight.swift
//  CascadeKit
//

import SwiftUI

/// AudioVolumeGlassLight puts `AudioVolumeGlassLightView` behind a volume capsule, in the same
/// frame, so the light rises from where the fill is. The glass takes at most eight lights from
/// everything in the notch, so the mixer gives one only to its first few app columns
/// (`AudioMixerComponent.litColumns`); the global volume always has its own.
struct AudioVolumeGlassLight: NSViewRepresentable {

    let widthRatio: CGFloat
    let level     : Double
    let isMuted   : Bool
    var tint      : AudioGlassTint = .volume
    var strength  : Double         = 1
    /// isLit turns the light off without removing the view, for a column past the lit ones.
    var isLit     : Bool           = true

    @Environment(\.accessibilityReduceTransparency)
    private var reducesTransparency

    func makeNSView(context: Context) -> AudioVolumeGlassLightView {
        AudioVolumeGlassLightView(
            widthRatio: widthRatio,
            strength  : strength
        )
    }

    func updateNSView(
        _ view : AudioVolumeGlassLightView,
        context: Context
    ) {
        view.configure(
            level    : level,
            isMuted  : isMuted,
            isEnabled: isLit && !reducesTransparency,
            tint     : tint
        )
    }

    static func dismantleNSView(
        _ view     : AudioVolumeGlassLightView,
        coordinator: ()
    ) {
        view.withdraw()
    }
}
