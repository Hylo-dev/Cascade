//
//  RollingDigitsLabel.swift
//  CascadeKit
//

import AppKit
import SwiftUI

/// RollingDigitsLabel is `RollingDigitsLabelView` for SwiftUI: the one way every number that
/// changes on the notch is drawn, Music's progress and the kernel's timers and countdowns alike.
/// Its digits roll in the render server, which costs a fraction of `numericText`; see the view
/// for the measurements.
///
/// Under Reduce Motion the digits change in place. Its size is the view's intrinsic size, the
/// width of the text it shows now.
public struct RollingDigitsLabel: NSViewRepresentable {

    public let text      : String
    public let font      : NSFont
    public let color     : NSColor
    public let countsDown: Bool
    public let animates  : Bool

    @Environment(\.accessibilityReduceMotion)
    private var reducesMotion

    /// animates is a second reason to hold the roll, for a caller that has its own: Music
    /// does not roll while the user scrubs. Reduce Motion always holds it.
    public init(
        text      : String,
        font      : NSFont,
        color     : NSColor,
        countsDown: Bool,
        animates  : Bool = true
    ) {
        self.text       = text
        self.font       = font
        self.color      = color
        self.countsDown = countsDown
        self.animates   = animates
    }

    public func makeNSView(context: Context) -> RollingDigitsLabelView {
        RollingDigitsLabelView(
            font : font,
            color: color
        )
    }

    public func updateNSView(
        _ view : RollingDigitsLabelView,
        context: Context
    ) {
        view.restyle(
            font : font,
            color: color
        )
        view.show(
            text,
            countsDown: countsDown,
            animates  : animates && !reducesMotion
        )
    }

    public func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView    : RollingDigitsLabelView,
        context   : Context
    ) -> CGSize? {
        nsView.intrinsicContentSize
    }
}
