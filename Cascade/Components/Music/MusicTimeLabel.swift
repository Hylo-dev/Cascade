//
//  MusicTimeLabel.swift
//  Cascade
//

import AppKit
import QuartzCore
import SwiftUI

/// MusicTimeLabel rolls only the digits that change, the way SwiftUI's
/// `numericText` does, but in the render server. That content transition
/// re-laid the text out on every display frame of each roll: measured at ~16 %
/// of a core for the two progress labels ticking once a second, against
/// ~0.2 % for static text. Here a tick sets the string of the one or two
/// digit layers that changed and a push transition moves the old digit out and
/// the new one in; the app does nothing in between.
struct MusicTimeLabel: NSViewRepresentable {
    let text      : String
    let countsDown: Bool
    let animates  : Bool

    func makeNSView(context: Context) -> MusicTimeLabelView {
        MusicTimeLabelView(font: .monospacedDigitSystemFont(ofSize: 11, weight: .regular))
    }

    func updateNSView(_ view: MusicTimeLabelView, context: Context) {
        view.show(
            text,
            countsDown: countsDown,
            animates  : animates
        )
    }

    func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView    : MusicTimeLabelView,
        context   : Context
    ) -> CGSize? {
        nsView.intrinsicContentSize
    }
}
