//
//  NotchBorderRenderer.swift
//  CascadeKit
//

import AppKit
import QuartzCore

/// The window compositor supplies the rim's backdrop and vibrancy. Cascade
/// never captures or reads other windows' pixels. This is visual contrast
/// adaptation, not a binary dark-background detector.
@MainActor
final class NotchBorderRenderer {
    static let visualOutset: CGFloat = 12
    let view = PassiveBorderEffectView(frame: .zero)
    let chargingGlow = CAGradientLayer()
    private(set) var appearance: NotchBorderAppearance = .neutral

    private let tintView = VibrantBorderTintView(frame: .zero)
    private let outlineMask = CALayer()
    private let haloMask = CAShapeLayer()
    private let glowMask = CAShapeLayer()
    private let rimMask = CAShapeLayer()
    private let topFadeMask = CAGradientLayer()
    private let bottomGlowOutline = CAShapeLayer()
    private var reducesTransparency = false
    private var increasesContrast = false
    private var hasPalette = false

    init() {
        view.wantsLayer = true
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .inactive
        view.isHidden = true
        view.layer?.zPosition = 1
        view.layer?.mask = outlineMask
        tintView.wantsLayer = true
        view.addSubview(tintView)

        for bloom in [haloMask, glowMask] {
            bloom.fillColor = nil
            bloom.strokeColor = NSColor.white.withAlphaComponent(0.10).cgColor
            bloom.lineWidth = 0.8
            bloom.shadowOffset = .zero
            bloom.shadowColor = NSColor.white.cgColor
        }
        haloMask.shadowRadius = 3.5
        haloMask.shadowOpacity = 0.10
        glowMask.shadowRadius = 1.5
        glowMask.shadowOpacity = 0.18
        rimMask.fillColor = nil
        rimMask.strokeColor = NSColor.white.cgColor
        rimMask.lineWidth = 0.65
        outlineMask.addSublayer(haloMask)
        outlineMask.addSublayer(glowMask)
        // Charging gets a short downward wash inside the existing halo gutter.
        // Its alpha reaches zero at the panel edge and never takes hit testing.
        // Keep the wash outside NSVisualEffectView: vibrancy can amplify a
        // broad alpha mask into a solid luminous strip on bright backdrops.
        chargingGlow.startPoint = CGPoint(x: 0.5, y: 0)
        chargingGlow.endPoint = CGPoint(x: 0.5, y: 1)
        chargingGlow.isHidden = true
        bottomGlowOutline.fillColor = nil
        bottomGlowOutline.strokeColor = NSColor.white.cgColor
        bottomGlowOutline.lineWidth = Self.visualOutset * 2
        chargingGlow.mask = bottomGlowOutline
        outlineMask.addSublayer(rimMask)
        outlineMask.mask = topFadeMask
        topFadeMask.startPoint = CGPoint(x: 0.5, y: 0)
        topFadeMask.colors = [
            NSColor.black.cgColor,
            NSColor.black.withAlphaComponent(0.95).cgColor,
            NSColor.black.withAlphaComponent(0.48).cgColor,
            NSColor.clear.cgColor,
            NSColor.clear.cgColor
        ]
        topFadeMask.locations = [0, 0.20, 0.55, 0.92, 1]
    }

    func setAppearance(
        _ appearance: NotchBorderAppearance,
        animated: Bool,
        reducesTransparency: Bool,
        increasesContrast: Bool
    ) {
        guard !hasPalette || self.appearance != appearance
            || self.reducesTransparency != reducesTransparency
            || self.increasesContrast != increasesContrast else { return }
        let shouldAnimate = hasPalette && animated
        self.appearance = appearance
        self.reducesTransparency = reducesTransparency
        self.increasesContrast = increasesContrast
        hasPalette = true

        let tint: NSColor = switch appearance {
        case .neutral:
            NSColor(srgbRed: 0.38, green: 0.38, blue: 0.40, alpha: reducesTransparency ? 1 : 0.55)
        case .connected, .charging:
            NSColor(srgbRed: 0.20, green: 0.88, blue: 0.46, alpha: reducesTransparency ? 1 : 0.90)
        case .chargingLowPower:
            NSColor(srgbRed: 1, green: 0.82, blue: 0.27, alpha: reducesTransparency ? 1 : 0.90)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        haloMask.isHidden = reducesTransparency
        glowMask.isHidden = reducesTransparency
        chargingGlow.colors = [tint.withAlphaComponent(0).cgColor, tint.withAlphaComponent(0.22).cgColor]
        chargingGlow.isHidden = view.isHidden || reducesTransparency
            || (appearance != .charging && appearance != .chargingLowPower)
        rimMask.lineWidth = increasesContrast ? 1.25 : 0.65
        if let layer = tintView.layer {
            let previous = layer.presentation()?.backgroundColor ?? layer.backgroundColor
            layer.removeAnimation(forKey: "backgroundColor")
            layer.backgroundColor = tint.cgColor
            if shouldAnimate, let previous {
                let animation = CABasicAnimation(keyPath: "backgroundColor")
                animation.fromValue = previous
                animation.toValue = tint.cgColor
                animation.duration = 0.24
                animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                layer.add(animation, forKey: "backgroundColor")
            }
        }
        CATransaction.commit()
    }

    /// The effect view keeps a fixed canvas frame with room for the halo. Only
    /// its mask follows the spring, reusing the fill's path without raster images.
    func apply(
        path: CGPath,
        canvasBounds: CGRect,
        isVisible: Bool,
        opacity: CGFloat,
        scale: CGFloat
    ) {
        let resolvedOpacity = opacity.isFinite ? min(1, max(0, opacity)) : 0
        let isHidden = !isVisible || resolvedOpacity == 0
        if view.isHidden != isHidden {
            view.isHidden = isHidden
            view.state = isHidden ? .inactive : .active
        }
        view.alphaValue = resolvedOpacity
        chargingGlow.opacity = Float(resolvedOpacity)
        chargingGlow.isHidden = isHidden || reducesTransparency
            || (appearance != .charging && appearance != .chargingLowPower)
        let canvas = canvasBounds.insetBy(dx: 0, dy: -Self.visualOutset)
        if view.frame != canvas {
            view.frame = canvas
            tintView.frame = view.bounds
        }
        // Translate the mask's coordinate system, not the shared CGPath.
        outlineMask.frame = view.bounds
        outlineMask.bounds = canvas
        let pathBounds = path.boundingBoxOfPath
        let bottomBounds = CGRect(
            x: pathBounds.minX - Self.visualOutset,
            y: pathBounds.minY - Self.visualOutset,
            width: pathBounds.width + Self.visualOutset * 2,
            height: Self.visualOutset + 1
        )
        chargingGlow.frame = bottomBounds
        chargingGlow.bounds = bottomBounds
        apply(path, to: bottomGlowOutline, bounds: bottomBounds, scale: scale)
        let effectBounds = pathBounds.insetBy(dx: -Self.visualOutset, dy: -Self.visualOutset)
        topFadeMask.frame = effectBounds
        topFadeMask.endPoint = CGPoint(
            x: 0.5,
            y: (pathBounds.maxY - effectBounds.minY) / max(1, effectBounds.height)
        )
        let outline = pathBounds.insetBy(dx: -2, dy: -2)
        apply(path, to: haloMask, bounds: outline, scale: scale)
        apply(path, to: glowMask, bounds: outline, scale: scale)
        apply(path, to: rimMask, bounds: outline, scale: scale)
    }

    private func apply(_ path: CGPath, to mask: CAShapeLayer, bounds: CGRect, scale: CGFloat) {
        mask.frame = bounds
        mask.bounds = bounds
        mask.path = path
        mask.contentsScale = scale
    }
}

/// The decorative surface must never take clicks from notch controls.
@MainActor
final class PassiveBorderEffectView: NSVisualEffectView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

/// Enable system contrast blending only for the rim's foreground tint.
@MainActor
private final class VibrantBorderTintView: NSView {
    override var allowsVibrancy: Bool { true }
}
