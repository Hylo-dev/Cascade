//
//  MusicProgressSlider.swift
//  Cascade
//

import AppKit
import SwiftUI

/// MusicProgressSlider keeps native seeking and accessibility while drawing
/// only the thick playback track. Drag and scroll previews never send player commands.
struct MusicProgressSlider: NSViewRepresentable {

    let position     : TimeInterval
    let duration     : TimeInterval
    let isEnabled    : Bool
    let onPreview    : (TimeInterval) -> Void
    let onCommit     : (TimeInterval) -> Void
    let onCancel     : () -> Void
    var trackIdentity: [String] = []

    func makeNSView(context: Context) -> MusicProgressControl {
        MusicProgressControl(frame: .zero)
    }

    func updateNSView(
        _ control: MusicProgressControl,
        context  : Context
    ) {
        control.trackIdentity = trackIdentity
        control.onPreview     = onPreview
        control.onCommit      = onCommit
        control.onCancel      = onCancel
        control.isEnabled     = isEnabled

        if !control.isScrubbing {
            control.minValue    = 0
            control.maxValue    = duration
            control.doubleValue = min(duration, max(0, position))
        }

        control.needsDisplay = true
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView    : MusicProgressControl,
        context   : Context
    ) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: 18)
    }
}
