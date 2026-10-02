import AppKit
import SwiftUI

/// RollingTimeLabel rolls only changed digits in the render server. Music and plugin timers
/// share the same 0.35-second push: each tick changes a few layers, with no per-frame layout.
/// The music labels' previous SwiftUI numericText transition measured about 16% of a core;
/// retaining their native layer implementation avoids reintroducing that layout work.
public struct RollingTimeLabel: NSViewRepresentable {

    public let text      : String
    public let countsDown: Bool
    public let animates  : Bool

    private let fontSize: CGFloat
    private let color   : NSColor

    public init(
        text      : String,
        countsDown: Bool,
        animates  : Bool,
        fontSize  : CGFloat = 11,
        color     : NSColor = .white.withAlphaComponent(0.55)
    ) {
        self.text       = text
        self.countsDown = countsDown
        self.animates   = animates
        self.fontSize   = fontSize
        self.color      = color
    }

    public func makeNSView(context: Context) -> NSView {
        RollingTimeLabelView(
            font : .monospacedDigitSystemFont(ofSize: fontSize, weight: .regular),
            color: color
        )
    }

    public func updateNSView(
        _ view : NSView,
        context: Context
    ) {
        (view as? RollingTimeLabelView)?.show(text, countsDown: countsDown, animates: animates)
    }

    public func sizeThatFits(
        _ proposal: ProposedViewSize,
        nsView    : NSView,
        context   : Context
    ) -> CGSize? {
        nsView.intrinsicContentSize
    }
}
