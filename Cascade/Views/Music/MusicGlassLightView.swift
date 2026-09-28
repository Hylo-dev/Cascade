//
//  MusicGlassLightView.swift
//  Cascade
//

import AppKit
import CascadeContracts
import CascadePresentation
import Observation
import SwiftUI

/// MusicGlassLightView draws nothing itself. Observation is armed only while it
/// is in a window, like the spectrum bars; leaving the window withdraws its light.
@MainActor
final class MusicGlassLightView: NSView {

    private let visual: MusicVisualState

    private weak var receiver: (any NotchGlassLightReceiving)?

    private var isPlaying     = false
    private var reducesMotion = false
    private var isEnabled     = true
    private var isObserving   = false

    init(visual: MusicVisualState) {
        self.visual = visual
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        guard window != nil else {
            withdraw()
            return
        }

        receiver = sequence(first: superview) { $0?.superview }
            .lazy
            .compactMap { $0 as? any NotchGlassLightReceiving }
            .first
        observeVisual()
    }

    override func setFrameOrigin(_ newOrigin: NSPoint) {
        super.setFrameOrigin(newOrigin)
        emit()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        emit()
    }

    func configure(
        isPlaying    : Bool,
        reducesMotion: Bool,
        isEnabled    : Bool
    ) {
        guard isPlaying != self.isPlaying
            || reducesMotion != self.reducesMotion
            || isEnabled != self.isEnabled
        else { return }

        self.isPlaying     = isPlaying
        self.reducesMotion = reducesMotion
        self.isEnabled     = isEnabled
        emit()
    }

    func withdraw() {
        receiver?.setGlassLights([], from: self)
    }

    /// observeVisual re-arms on the next main-actor turn, after the change has
    /// been stored, exactly as MusicSpectrumLayerView does.
    private func observeVisual() {
        guard window != nil, !isObserving else { return }

        isObserving = true
        withObservationTracking {
            emit()
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }

                self.isObserving = false
                self.observeVisual()
            }
        }
    }

    /// emit places the halo and the first wash on the cover and the second
    /// sampled hue lower in the glass. Positions and radii are normalized to
    /// the receiver's outline, as every glass light is.
    private func emit() {
        let colors = visual.artworkColors
        guard let receiver, window != nil, isEnabled, visual.artwork != nil, !colors.isEmpty else {
            withdraw()
            return
        }

        let outline = receiver.glassLightBounds
        guard outline.width > 0, outline.height > 0 else { return }

        let center      = convert(CGPoint(x: bounds.midX, y: bounds.midY), to: receiver)
        let normalizedX = min(1, max(0, (center.x - outline.minX) / outline.width))
        let normalizedY = min(1, max(0, (outline.maxY - center.y) / outline.height))

        let response = MusicGlassLightResponse(
            bands        : visual.bands,
            isPlaying    : isPlaying,
            reducesMotion: reducesMotion
        )

        func light(
            _ color  : MusicArtworkColor,
            x        : Double,
            y        : Double,
            radius   : Double,
            intensity: Double
        ) -> GlassLight? {
            try? GlassLight(
                x        : x,
                y        : y,
                radius   : min(1, max(0.01, radius)),
                red      : color.red,
                green    : color.green,
                blue     : color.blue,
                intensity: min(1, max(0, intensity))
            )
        }

        var lights: [GlassLight?] = []
        if isPlaying {
            // The former glow drawn over the content: a tight ring around the
            // cover, now beneath the glass.
            lights.append(light(
                colors[0],
                x        : normalizedX,
                y        : normalizedY,
                radius   : (bounds.width / 2 + 24) / outline.width,
                intensity: 0.6
            ))
        }
        lights.append(light(
            colors[0],
            x        : normalizedX,
            y        : normalizedY,
            radius   : response.radius,
            intensity: response.intensity
        ))
        if colors.count > 1 {
            lights.append(light(
                colors[1],
                x        : 0.64,
                y        : 0.92,
                radius   : response.radius,
                intensity: response.intensity * 0.7
            ))
        }

        receiver.setGlassLights(lights.compactMap { $0 }, from: self)
    }
}
