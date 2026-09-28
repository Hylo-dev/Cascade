//
//  MusicSpectrumBars.swift
//  Cascade
//

import AppKit
import CascadeKit
import CoreImage
import Observation
import QuartzCore
import SwiftUI

/// MusicSpectrumBars uses one album gradient across all six measured bands.
/// The resting height equals the width, so silence resolves into round dots.
///
/// The bars are Core Animation layers rather than SwiftUI shapes. A SwiftUI
/// `.animation` re-lays the capsules out in-process on every display frame:
/// measured at ~6 % of a core for the always-visible compact bars at 120 Hz.
/// Here each 30 Hz analysis tick sets six layer frames and the render server
/// interpolates them at the display's refresh, the same smoothness for ~1 %.
/// Bands reach the layers through Observation directly, so a tick never
/// invalidates SwiftUI; only size and accessibility settings pass through it.
struct MusicSpectrumBars: View {
    let visual: MusicVisualState
    let width : CGFloat
    let height: CGFloat
    var isCompact = false

    @Environment(\.displayScale)
    private var displayScale
    @Environment(\.accessibilityReduceTransparency)
    private var reduceTransparency
    @Environment(\.accessibilityReduceMotion)
    private var reduceMotion

    var body: some View {
        MusicSpectrumLayerRepresentable(
            visual   : visual,
            size     : CGSize(width: max(0, width), height: max(0, height)),
            scale    : max(1, displayScale),
            showsHalo: isCompact && !reduceTransparency,
            animates : !reduceMotion
        )
        .frame(width: max(0, width), height: max(0, height))
        .accessibilityHidden(true)
    }
}

struct MusicSpectrumLayerRepresentable: NSViewRepresentable {
    let visual   : MusicVisualState
    let size     : CGSize
    let scale    : CGFloat
    let showsHalo: Bool
    let animates : Bool

    func makeNSView(context: Context) -> MusicSpectrumLayerView {
        MusicSpectrumLayerView(visual: visual)
    }

    func updateNSView(_ view: MusicSpectrumLayerView, context: Context) {
        view.configure(
            size     : size,
            scale    : scale,
            showsHalo: showsHalo,
            animates : animates
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView    : MusicSpectrumLayerView,
        context   : Context
    ) -> CGSize? {
        size
    }
}
