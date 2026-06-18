//
//  NotchHostView.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI

/// NotchHostView is the layer-backed canvas the notch chrome is drawn in.
///
/// It owns a single `CAShapeLayer` whose `path` is the notch outline. Morphing
/// the notch is just assigning a new path each frame — the GPU rasterizes it —
/// so we never override `draw(_:)`. The view spans a fixed band across the top
/// of the active screen and does *not* resize during a morph; only the layer
/// path changes, which keeps the window geometry (an expensive thing to touch)
/// completely still while the notch animates.
///
/// Hit-testing is deliberately narrow: the view returns itself only for points
/// inside the current shape, so clicks anywhere else in the band pass straight
/// through to whatever is behind (the menu bar, the desktop, other windows).
final class NotchHostView: NSView {

    private let shapeLayer = CAShapeLayer()

    /// Hosts the SwiftUI content shown inside the open notch (the widgets). It
    /// sits above the shape layer and is sized/placed to the open notch's
    /// interior; it is hidden while the notch is closed.
    private let contentHost = NSHostingView(rootView: AnyView(EmptyView()))

    /// The interactive hit region, in view coordinates, kept in sync with the
    /// morph so the overlay only swallows clicks where the notch actually is.
    private var hitRegion = CGRect.zero

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        commonInit()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {

        wantsLayer = true

        shapeLayer.fillColor   = NSColor.black.cgColor
        shapeLayer.anchorPoint = .zero
        shapeLayer.frame       = bounds

        layer?.addSublayer(shapeLayer)

        contentHost.isHidden = true
        addSubview(contentHost)
    }

    /// Set the notch fill. Called once by the controller from the configuration;
    /// the renderer keeps the path moving, the color is stable. The SwiftUI
    /// `Color` is bridged to a `CGColor` here, at the AppKit boundary.
    func setChromeColor(_ color: Color) {
        shapeLayer.fillColor = NSColor(color).cgColor
    }

    /// Show or hide the widget content and place it within the open notch.
    func setContent(
        _ view   : AnyView,
        frame    : CGRect,
        isVisible: Bool
    ) {
        contentHost.rootView = view
        contentHost.frame    = frame
        contentHost.isHidden = !isVisible
    }

    // The notch hangs from the top, so we keep the default bottom-left origin
    // (y grows upward); the renderer hands us geometry in those coordinates.
    override var isFlipped: Bool {
        false
    }

    /// Push a freshly resolved geometry to the screen.
    ///
    /// `isChromeVisible` is false on displays without a hardware notch: there we
    /// draw nothing, but `hitRegion` still tracks the interactive zone so the
    /// gestures keep working — the contract is interaction everywhere, chrome
    /// only where the hardware notch is.
    func apply(
        geometry       : NotchGeometry,
        centerX        : CGFloat,
        topY           : CGFloat,
        isChromeVisible: Bool
    ) {

        // Per-frame geometry changes must not animate implicitly — the spring is
        // already the animation. A no-action transaction stops Core Animation
        // from adding its own quarter-second fade to every path swap.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        shapeLayer.frame = bounds

        let path = CGPath.notch(
            geometry: geometry,
            centerX : centerX,
            topY    : topY
        )

        shapeLayer.path     = path
        shapeLayer.isHidden = !isChromeVisible

        CATransaction.commit()

        hitRegion = path.boundingBoxOfPath
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        hitRegion.contains(point) ? self : nil
    }
}
