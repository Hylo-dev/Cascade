//
//  NotchGlassRenderer.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import CoreImage
import QuartzCore
import SwiftUI

/// NotchGlassRendering keeps native material updates separate from widget layout.
@MainActor
protocol NotchGlassRendering {
    var view: NSView { get }
    var isSupported: Bool { get }

    func setColor(_ color: Color)
    func setLights(_ lights: [GlassLight])

    /// `body` is where the notch is this frame and `target` where its morph is
    /// heading; both come from the same geometry that produced `path`.
    func apply(
        path        : CGPath,
        body        : NotchGlassBody,
        target      : NotchGlassBody,
        canvasBounds: CGRect,
        progress    : CGFloat,
        isVisible   : Bool
    )
}

/// NotchGlassBody is the rectangle the native glass covers: the notch body with
/// its convex bottom corners, extended one radius above the top edge so only
/// the bottom corners round. The concave shoulders and a detached bubble stay
/// outside it, under the near-opaque top of the tint gradient, where the old
/// full-outline glass was hidden anyway.
nonisolated struct NotchGlassBody: Equatable, Sendable {
    static let zero = NotchGlassBody(rect: .zero, cornerRadius: 0)

    let rect        : CGRect
    let cornerRadius: CGFloat

    init(rect: CGRect, cornerRadius: CGFloat) {
        self.rect         = rect
        self.cornerRadius = cornerRadius
    }

    init(geometry: NotchGeometry, centerX: CGFloat, topY: CGFloat) {
        let radius = max(0, min(geometry.bottomCornerRadius, geometry.height / 2, geometry.width / 2))
        self.init(
            rect: CGRect(
                x     : centerX - geometry.leftExtent,
                y     : topY - geometry.height,
                width : geometry.width,
                height: geometry.height + radius
            ),
            cornerRadius: radius
        )
    }

    /// transform maps a layer laid out at `reference` onto this body without a
    /// new layout. `anchor` is the layer's normalized anchor point: the layer
    /// renders local point p at origin + A + T(p − A), and T solves that to
    /// land on this body's origin + S·p for the per-axis scale S.
    func transform(
        from reference: NotchGlassBody,
        anchor        : CGPoint
    ) -> CGAffineTransform {
        let source = reference.rect
        guard source.width > 0, source.height > 0 else { return .identity }
        let scaleX = rect.width / source.width
        let scaleY = rect.height / source.height
        let anchorX = anchor.x * source.width
        let anchorY = anchor.y * source.height
        return CGAffineTransform(
            a : scaleX,
            b : 0,
            c : 0,
            d : scaleY,
            tx: rect.minX - source.minX + (scaleX - 1) * anchorX,
            ty: rect.minY - source.minY + (scaleY - 1) * anchorY
        )
    }
}

/// NotchGlassRenderer draws the notch's Liquid Glass with AppKit and Core
/// Animation only. Every per-frame input is a layer property that the render
/// server composites, so nothing is drawn in this process.
///
/// The former SwiftUI `glassEffect(in:)` received a new outline and tint on
/// each of the 120 morph frames and re-resolved the glass material every time:
/// measured at ~43 % CPU and ~110 MB peak during hover. NSGlassEffectView is
/// itself SwiftUI-backed, so resizing it per frame still costs a layout pass.
/// Instead the glass is laid out once at the body the morph is heading to and a
/// layer transform maps it onto the current body, so its rim still follows the
/// moving edge. The exact silhouette, shoulders included, comes from a shape
/// mask. Measured in isolation: ~2–3 % CPU and 13 MB for the same morph.
///
/// The glass is Apple's own, with its lens switched back on (NotchGlassLens):
/// clear, refracting what lies behind its edge. Everything the glass should
/// absorb lies below it, where its backdrop samples it: the vertical black
/// gradient, clear toward the bottom edge where the lens shows, and the
/// widgets' lights, added onto that black. The smoked glass then darkens and
/// bends both. The lights fade out smoothly toward the top edge, into black
/// the glass keeps pure, so no edge of the black shows through them. Above the
/// glass only a solid shade stands in for the tint while the notch opens.
@MainActor
final class NotchGlassRenderer: NotchGlassRendering {
    let view: NSView = PassiveNotchGlassView(frame: .zero)
    let isSupported: Bool

    private let outlineMask = CAShapeLayer()
    private let backingView = NSView()
    private let lightsView  = NSView()
    private let overlayView = NSView()
    private let lightsLayer = CALayer()
    private let shadeLayer  = CALayer()
    private let tintLayer   = CAGradientLayer()
    private let lightsFade  = CAGradientLayer()
    private var lightLayers : [CAGradientLayer] = []
    private var lights      : [GlassLight] = []
    private var color       : Color = .black
    /// NSGlassEffectView on macOS 26; a stored property cannot carry that
    /// availability, so it is kept as its superclass.
    private var glass       : NSView?
    private var reference   : NotchGlassBody?
    private var lensAttempts = 0

    init() {
        view.wantsLayer = true
        view.clipsToBounds = false
        view.isHidden = true
        view.setAccessibilityElement(false)
        view.layer?.mask = outlineMask

        // Layer-hosting views keep AppKit from reordering these sublayers
        // around the glass view's own layer.
        for hosted in [backingView, lightsView, overlayView] {
            hosted.layer = CALayer()
            hosted.wantsLayer = true
            hosted.autoresizingMask = [.width, .height]
        }
        lightsView.layerUsesCoreImageFilters = true
        lightsView.layer?.addSublayer(lightsLayer)
        backingView.layer?.addSublayer(tintLayer)
        overlayView.layer?.addSublayer(shadeLayer)
        for gradient in [tintLayer, lightsFade] {
            gradient.startPoint = CGPoint(x: 0.5, y: 1)
            gradient.endPoint   = CGPoint(x: 0.5, y: 0)
        }
        tintLayer.locations = [0, 0.58, 0.76, 0.90]
        // Light is gone over the hardware cutout's depth and returns along a
        // smootherstep: a linear ramp leaves a visible band where it starts.
        lightsFade.locations = [0, 0.14, 0.24, 0.34, 0.44, 0.56]
        lightsFade.colors = [0, 0.03, 0.18, 0.46, 0.78, 1].map {
            NSColor.black.withAlphaComponent($0).cgColor
        }
        lightsLayer.mask = lightsFade

        view.addSubview(backingView)
        view.addSubview(lightsView)
        if #available(macOS 26, *) {
            isSupported = true
            let glass = NSGlassEffectView()
            // Layer-backed before it joins a window: placement uses its layer.
            glass.wantsLayer = true
            glass.style = .clear
            view.addSubview(glass)
            self.glass = glass
            // An appearance change rebuilds the glass's filter at its defaults.
            (view as? PassiveNotchGlassView)?.onAppearanceChange = { [weak self] in
                self?.reopenLens()
            }
        } else {
            isSupported = false
        }
        view.addSubview(overlayView)
        applyColor()
    }

    func setColor(_ color: Color) {
        guard self.color != color else { return }
        self.color = color
        applyColor()
    }

    /// setLights reuses its layers. A spectrum-driven light changes up to 30
    /// times a second; rebuilding every gradient layer and its compositing
    /// filter on each change cost ~1 % of a core on its own. Colors are written
    /// only when a hue changes, intensity is the layer's opacity, and a change
    /// of value alone eases over one analysis interval in the render server.
    func setLights(_ lights: [GlassLight]) {
        let bounded = Array(lights.prefix(GlassLight.maximumCount))
        guard self.lights != bounded else { return }
        // Only reused layers carry the previous colors; new ones start bare.
        let previous = lightLayers.count == bounded.count ? self.lights : []
        self.lights = bounded
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if lightLayers.count != bounded.count {
            lightLayers.forEach { $0.removeFromSuperlayer() }
            lightLayers = bounded.map { _ in Self.makeLightLayer() }
            lightLayers.forEach(lightsLayer.addSublayer)
        }
        for (index, light) in bounded.enumerated() {
            let layer = lightLayers[index]
            let old = previous.indices.contains(index) ? previous[index] : nil
            guard old.map({ ($0.red, $0.green, $0.blue) != (light.red, light.green, light.blue) }) ?? true else { continue }
            let colors = Self.colors(of: light)
            if old != nil {
                // A new hue, such as the next track's cover, crossfades with it.
                let fade = CABasicAnimation(keyPath: "colors")
                fade.fromValue = layer.presentation()?.colors ?? layer.colors
                fade.toValue = colors
                fade.duration = 0.45
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(fade, forKey: "colors")
            }
            layer.colors = colors
        }
        if previous.count == bounded.count {
            CATransaction.setDisableActions(false)
            CATransaction.setAnimationDuration(1.0 / 30)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        }
        for (layer, light) in zip(lightLayers, bounded) {
            layer.opacity = Float(light.intensity)
        }
        layoutLights()
        CATransaction.commit()
    }

    /// apply hides the stack when idle or inaccessible, so the resting hardware
    /// notch never keeps a backdrop effect composited. The mask follows the
    /// outline even while hidden, like every other consumer of the path. The
    /// caller's transaction already disables implicit actions.
    func apply(
        path        : CGPath,
        body        : NotchGlassBody,
        target      : NotchGlassBody,
        canvasBounds: CGRect,
        progress    : CGFloat,
        isVisible   : Bool
    ) {
        if view.frame != canvasBounds {
            view.frame = canvasBounds
            let local = CGRect(origin: .zero, size: canvasBounds.size)
            outlineMask.frame = local
            shadeLayer.frame  = local
        }
        outlineMask.path = path
        let isVisible = isSupported && isVisible
        if view.isHidden == isVisible {
            view.isHidden = !isVisible
            // The glass builds its layers on the first commit that shows it.
            if isVisible { reopenLens() }
        }
        guard isVisible else {
            reference = nil
            return
        }
        placeGlass(body: body, target: target)

        let outline = path.boundingBoxOfPath
        let reveal = min(1, max(0, (progress - 0.3) / 0.7))
        shadeLayer.opacity  = Float(0.95 * (1 - reveal))
        tintLayer.frame     = outline
        lightsLayer.opacity = Float(reveal)
        if lightsLayer.frame != outline {
            lightsLayer.frame = outline
            lightsFade.frame  = CGRect(origin: .zero, size: outline.size)
            layoutLights()
        }
    }

    /// placeGlass lays the glass out once per destination. An opening heads to a
    /// larger body; a collapse keeps the larger layout and scales it down, so
    /// the glass is never stretched past the size it was laid out at. Settling
    /// on the target lays it out exactly, leaving an identity transform at rest.
    private func placeGlass(body: NotchGlassBody, target: NotchGlassBody) {
        guard let glass, let layer = glass.layer else { return }
        if body == target || reference == nil || target.rect.height >= body.rect.height,
           reference != target {
            reference = target
            layer.setAffineTransform(.identity)
            glass.frame = target.rect
            if #available(macOS 26, *), let glass = glass as? NSGlassEffectView {
                // The outline normalizes a native continuous corner to span
                // exactly its radius; the native glass takes the nominal
                // radius, which reaches farther. Convert, or the rounder glass
                // leaves an uncovered crescent inside each bottom corner.
                glass.cornerRadius = target.cornerRadius / ContinuousNotchCorner.spanPerRadius
            }
            // A new size rebuilds the glass's filter, back to its defaults.
            reopenLens()
        }
        guard let reference else { return }
        layer.setAffineTransform(body.transform(from: reference, anchor: layer.anchorPoint))
    }

    /// reopenLens opens the lens once the glass has settled on its filter. The
    /// glass rebuilds that filter after a first show, a new size, tint or
    /// appearance, at a later commit rather than at once, so the lens is
    /// applied on the next turns of the run loop until a turn finds it still
    /// open, proof that it outlived a commit. Bounded: a handful of turns per
    /// change, nothing per frame and nothing while the notch rests.
    private func reopenLens() {
        let isSettling = lensAttempts > 0
        lensAttempts = 6
        guard !isSettling else { return }
        DispatchQueue.main.async { [weak self] in self?.settleLens() }
    }

    private func settleLens() {
        guard lensAttempts > 0, let glass, let layer = glass.layer, !view.isHidden else {
            lensAttempts = 0
            return
        }
        lensAttempts -= 1
        glass.layoutSubtreeIfNeeded()
        guard NotchGlassLens.open(in: layer) != .alreadyOpen, lensAttempts > 0 else {
            lensAttempts = 0
            return
        }
        DispatchQueue.main.async { [weak self] in self?.settleLens() }
    }

    private func applyColor() {
        let base = NSColor(color)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shadeLayer.backgroundColor = base.cgColor
        // Solid well past the hardware cutout's depth, eased out below it, and
        // clear over the bottom tenth, where the lens shows.
        // Beneath the glass, which keeps it pure black (NotchGlassLens).
        tintLayer.colors = [
            base,
            base,
            base.withAlphaComponent(base.alphaComponent * 0.35),
            base.withAlphaComponent(0)
        ].map(\.cgColor)
        CATransaction.commit()
        if #available(macOS 26, *), let glass = glass as? NSGlassEffectView {
            // A smoked glass at full reveal: darker, not frosted. The shade
            // layer darkens it further while opening.
            glass.tintColor = base.withAlphaComponent(base.alphaComponent * 0.25)
            if !view.isHidden { reopenLens() }
        }
    }

    /// layoutLights places each light as the former Canvas did: its center at
    /// (x, y) of the outline's bounds, y measured from the top, and its radius
    /// a fraction of the bounds' width.
    private func layoutLights() {
        let size = lightsLayer.bounds.size
        for (layer, light) in zip(lightLayers, lights) {
            let radius = CGFloat(light.radius) * size.width
            layer.frame = CGRect(
                x     : CGFloat(light.x) * size.width - radius,
                y     : (1 - CGFloat(light.y)) * size.height - radius,
                width : radius * 2,
                height: radius * 2
            )
        }
    }

    private static func makeLightLayer() -> CAGradientLayer {
        let layer = CAGradientLayer()
        layer.type = .radial
        layer.startPoint = CGPoint(x: 0.5, y: 0.5)
        layer.endPoint   = CGPoint(x: 1, y: 1)
        layer.locations = [0, 0.25, 0.65, 1]
        // The former Canvas blended lights with plusLighter.
        layer.compositingFilter = CIFilter(name: "CIAdditionCompositing")
        return layer
    }

    /// The falloff at full strength; the layer's opacity scales it.
    private static func colors(of light: GlassLight) -> [CGColor] {
        let color = NSColor(
            srgbRed: CGFloat(light.red),
            green  : CGFloat(light.green),
            blue   : CGFloat(light.blue),
            alpha  : 1
        )
        return [1, 0.55, 0.12, 0].map { color.withAlphaComponent($0).cgColor }
    }
}

/// NotchGlassLens turns back on the lens that macOS leaves off on a glass the
/// size of an open notch. Past a certain size NSGlassEffectView frosts its
/// `glassBackground` filter (refraction opacity 0, blur radius 10), so the
/// notch read as a grey panel. With the blur at 0 and the refraction at full
/// opacity it is the clear glass of Apple's controls: the desktop shows
/// through untouched in the middle and bends through the edge, with Apple's
/// own lens profile (-60 over 20 pt at this size). Its face also lifts black
/// to a grey, dims white to 80 % and lays a 5 % white veil over both; all three
/// are undone, so the black beneath the glass stays as black as the hardware
/// cutout and the clear edge darkens only by the glass's own smoke.
///
/// The filter is private Core Animation API, reached by key. Only a filter and
/// keys that exist are touched, so if macOS renames them the glass stays
/// Apple's frosted default rather than breaking. Cost: a walk over the glass's
/// ~20 layers a few times per rebuild, nothing per frame.
@MainActor
enum NotchGlassLens {
    static let tuning: [String: Double] = [
        "inputBlurRadius"          : 0,
        "inputRefractionOpacity"   : 1,
        "inputFaceColorMatrixBlack": 0,
        "inputFaceColorMatrixWhite": 1,
    ]
    static let faceFillKey = "inputFaceColorMatrixFillColor"
    static let faceFill    = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0)

    enum Outcome: Equatable {
        /// The glass has not built its filter yet.
        case missing
        case opened
        /// Every tuned key already held its value.
        case alreadyOpen
    }

    @discardableResult
    static func open(in root: CALayer) -> Outcome {
        var outcome = Outcome.missing
        for layer in backdrops(in: root) {
            guard let filter = layer.filters?
                    .compactMap({ $0 as? NSObject })
                    .first(where: { name(of: $0) == "glassBackground" }),
                  let keys = filter.perform(NSSelectorFromString("inputKeys"))?
                    .takeUnretainedValue() as? [String]
            else { continue }
            if outcome == .missing { outcome = .alreadyOpen }
            for (key, value) in tuning where keys.contains(key) {
                guard (filter.value(forKey: key) as? Double) != value else { continue }
                layer.setValue(value, forKeyPath: "filters.glassBackground.\(key)")
                outcome = .opened
            }
            if keys.contains(faceFillKey),
               filter.value(forKey: faceFillKey).map({ !CFEqual($0 as AnyObject, faceFill) }) ?? true {
                layer.setValue(faceFill, forKeyPath: "filters.glassBackground.\(faceFillKey)")
                outcome = .opened
            }
        }
        return outcome
    }

    private static func name(of filter: NSObject) -> String? {
        filter.responds(to: NSSelectorFromString("name")) ? filter.value(forKey: "name") as? String : nil
    }

    private static func backdrops(in layer: CALayer) -> [CALayer] {
        let own = NSStringFromClass(type(of: layer)) == "CABackdropLayer" ? [layer] : []
        return own + (layer.sublayers ?? []).flatMap { backdrops(in: $0) }
    }
}

/// PassiveNotchGlassView never intercepts the controls hosted above the material.
@MainActor
private final class PassiveNotchGlassView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}
