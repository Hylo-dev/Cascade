//
//  SpotlightDropletGlassView.swift
//  Cascade
//

import AppKit
import QuartzCore

/// SpotlightDropletGlassView lets AppKit merge two real Liquid Glass surfaces.
///
/// Clear glass preserves the desktop backdrop. A translucent black scrim inside
/// the departing capsule approaches Campo's dark surface without painting an
/// opaque gray gradient over the glass. No search content is drawn.
@available(macOS 26.0, *)
@MainActor
final class SpotlightDropletGlassView: NSView {
    private let glassContainer = NSGlassEffectContainerView()
    private let scrim = CAGradientLayer()
    private let scrimView = NSView()
    var spacing: CGFloat {
        get { glassContainer.spacing }
        set { glassContainer.spacing = newValue }
    }

    private let sourceGlass  = NSGlassEffectView()
    private let dropletGlass = NSGlassEffectView()
    private let canvasBounds : CGRect

    init(timeline: SpotlightDropletTimeline) {
        canvasBounds = timeline.layout.canvasBounds

        super.init(
            frame: CGRect(
                origin : .zero,
                size   : canvasBounds.size
            )
        )

        wantsLayer = true
        glassContainer.frame = bounds
        glassContainer.autoresizingMask = [.width, .height]
        glassContainer.wantsLayer = true
        addSubview(glassContainer)
        let surfaceContainer = NSView(frame: bounds)
        surfaceContainer.autoresizingMask = [.width, .height]
        glassContainer.contentView = surfaceContainer
        spacing = timeline.mergeSpacing

        // Matching clear styles keeps the native merge and refraction. Regular
        // glass adds a pale fill that is absent from the observed Campo field.
        sourceGlass.style        = .clear
        sourceGlass.tintColor    = .black
        sourceGlass.cornerRadius = min(
            timeline.layout.sourceBounds.width,
            timeline.layout.sourceBounds.height
        ) / 2
        sourceGlass.frame = localBounds(timeline.layout.sourceBounds)
        sourceGlass.alphaValue = timeline.reducesMotion ? 0 : 1

        dropletGlass.style     = .clear
        dropletGlass.tintColor = .black.withAlphaComponent(0.35)
        scrimView.wantsLayer = true
        scrimView.layer?.masksToBounds = true
        scrim.startPoint = CGPoint(x: 0.5, y: 1)
        scrim.endPoint = CGPoint(x: 0.5, y: 0)
        scrim.colors = [NSColor.black.withAlphaComponent(0.96).cgColor,
                        NSColor.black.withAlphaComponent(0.30).cgColor]
        scrimView.layer?.addSublayer(scrim)
        dropletGlass.contentView = scrimView

        surfaceContainer.addSubview(sourceGlass)
        surfaceContainer.addSubview(dropletGlass)

        setAccessibilityElement(false)
        sourceGlass.setAccessibilityElement(false)
        dropletGlass.setAccessibilityElement(false)
        apply(timeline.frame(at: 0))
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// apply commits one value-only frame; AppKit owns refraction and material rendering.
    func apply(_ frame: SpotlightDropletFrame) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        spacing                   = frame.mergeSpacing
        dropletGlass.frame        = localBounds(frame.dropletBounds)
        scrimView.frame           = dropletGlass.bounds
        scrimView.layer?.cornerRadius = frame.cornerRadius
        scrim.frame               = scrimView.bounds
        dropletGlass.cornerRadius = frame.cornerRadius
        dropletGlass.alphaValue   = frame.opacity
        CATransaction.commit()
    }

    private func localBounds(_ globalBounds: CGRect) -> CGRect {
        globalBounds.offsetBy(
            dx : -canvasBounds.minX,
            dy : -canvasBounds.minY
        )
    }
}
