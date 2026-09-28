//
//  MusicSpectrumLayerView.swift
//  Cascade
//

import AppKit
import CascadeKit
import CoreImage
import Observation
import QuartzCore
import SwiftUI

/// MusicSpectrumLayerView owns the bar layers: the album gradient masked by six
/// capsules and, for the compact bars, a faint blurred copy behind it as the
/// halo. The blur is a render-server filter, so it costs the app nothing per
/// frame. Observation is armed only while the view is in a window.
@MainActor
final class MusicSpectrumLayerView: NSView {
    private let visual       : MusicVisualState
    private let barGradient  = CAGradientLayer()
    private let barMask      = CALayer()
    private let haloContainer = CALayer()
    private let haloGradient = CAGradientLayer()
    private let haloMask     = CALayer()
    private var barLayers    : [CALayer] = []
    private var haloLayers   : [CALayer] = []
    private var bands        = AudioSpectrumFrame.silence.bands
    private var palette      : [Color] = []
    private var size         = CGSize.zero
    private var scale        : CGFloat = 0
    private var animates     = true
    private var isObserving  = false

    init(visual: MusicVisualState) {
        self.visual = visual
        super.init(frame: .zero)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        for gradient in [barGradient, haloGradient] {
            gradient.startPoint = CGPoint(x: 0, y: 0.5)
            gradient.endPoint   = CGPoint(x: 1, y: 0.5)
        }
        barLayers  = Self.makeCapsules(in: barMask)
        haloLayers = Self.makeCapsules(in: haloMask)
        barGradient.mask  = barMask
        haloGradient.mask = haloMask
        // The blur sits on a container so it applies after the mask: blurring
        // the masked gradient itself would be clipped back to the capsules.
        haloContainer.addSublayer(haloGradient)
        haloContainer.opacity = 0.2
        haloContainer.filters = CIFilter(
            name      : "CIGaussianBlur",
            parameters: [kCIInputRadiusKey: 1.2]
        ).map { [$0] }
        layer?.addSublayer(haloContainer)
        layer?.addSublayer(barGradient)
    }

    required init?(coder: NSCoder) { nil }

    /// Clicks belong to the SwiftUI activity around the bars.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeVisual()
    }

    func configure(
        size     : CGSize,
        scale    : CGFloat,
        showsHalo: Bool,
        animates : Bool
    ) {
        self.animates = animates
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        haloContainer.isHidden = !showsHalo
        if size != self.size || scale != self.scale {
            self.size  = size
            self.scale = scale
            let bounds = CGRect(origin: .zero, size: size)
            for layer in [barGradient, barMask, haloContainer, haloGradient, haloMask] {
                layer.frame         = bounds
                layer.contentsScale = scale
            }
            let radius = barWidth / 2
            for capsule in barLayers + haloLayers {
                capsule.cornerRadius  = radius
                capsule.contentsScale = scale
            }
            layoutBars()
        }
        CATransaction.commit()
    }

    /// observeVisual reads bands and palette under Observation and re-arms after
    /// each change. onChange fires before the new value is stored, so the next
    /// read happens on the following main-actor turn. A view that has left its
    /// window stops re-arming; returning to one resumes with current values.
    private func observeVisual() {
        guard window != nil, !isObserving else { return }
        isObserving = true
        withObservationTracking {
            apply(bands: visual.bands, palette: visual.palette)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.isObserving = false
                self.observeVisual()
            }
        }
    }

    private func apply(bands: [Float], palette: [Color]) {
        if palette != self.palette {
            self.palette = palette
            let colors = palette.map { NSColor($0).cgColor }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            barGradient.colors  = colors
            haloGradient.colors = colors
            CATransaction.commit()
        }
        self.bands = bands
        CATransaction.begin()
        if animates {
            // One analysis interval: AudioSpectrumPCMExchange publishes at
            // 30 Hz, so each frame lands as the next one arrives.
            CATransaction.setAnimationDuration(1.0 / 30)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        } else {
            CATransaction.setDisableActions(true)
        }
        layoutBars()
        CATransaction.commit()
    }

    private var barWidth: CGFloat {
        (max(0, min(2.4, size.width / 12, size.height)) * scale).rounded() / max(1, scale)
    }

    private func layoutBars() {
        guard scale > 0, bands.count == barLayers.count else { return }
        let barWidth = self.barWidth
        let stride   = max(0, (size.width - barWidth) / 5)
        for index in barLayers.indices {
            let barHeight = max(barWidth, (size.height * CGFloat(bands[index]) * scale).rounded() / scale)
            // Equal dimensions alone are not enough at this size:
            // fractional origins rasterize circles as flattened dots.
            let frame = CGRect(
                x     : (CGFloat(index) * stride * scale).rounded() / scale,
                y     : ((size.height - barHeight) / 2 * scale).rounded() / scale,
                width : barWidth,
                height: barHeight
            )
            barLayers[index].frame  = frame
            haloLayers[index].frame = frame
        }
    }

    private static func makeCapsules(in mask: CALayer) -> [CALayer] {
        (0..<6).map { _ in
            let capsule = CALayer()
            capsule.backgroundColor = NSColor.white.cgColor
            mask.addSublayer(capsule)
            return capsule
        }
    }
}
