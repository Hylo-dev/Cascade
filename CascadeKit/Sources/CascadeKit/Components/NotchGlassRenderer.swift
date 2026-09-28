//
//  NotchGlassRenderer.swift
//  CascadeKit
//

import AppKit
import CascadeContracts
import Observation
import SwiftUI

/// NotchGlassRendering keeps native material updates separate from widget layout.
@MainActor
protocol NotchGlassRendering {
    var view: NSView { get }
    var isSupported: Bool { get }

    func setColor(_ color: Color)
    func setLights(_ lights: [GlassLight])
    func apply(path: CGPath, canvasBounds: CGRect, progress: CGFloat, isVisible: Bool)
}

/// NotchGlassRenderer gives the compositor the actual notch outline, including
/// its concave shoulders and detached activity. Masking an AppKit glass rectangle
/// would clip its pixels but leave its refraction following the wrong perimeter.
/// Only this small material host observes morph frames; widget roots stay intact.
@MainActor
final class NotchGlassRenderer: NotchGlassRendering {
    let view: NSView = PassiveNotchGlassView(frame: .zero)
    let isSupported: Bool
    private let state = NotchGlassState()

    init() {
        view.wantsLayer = true
        view.clipsToBounds = false
        view.isHidden = true
        view.setAccessibilityElement(false)

        if #available(macOS 26, *) {
            isSupported = true
            let host = NSHostingView(rootView: NotchGlassSurface(state: state))
            host.sizingOptions = []
            host.frame = view.bounds
            host.autoresizingMask = [.width, .height]
            host.clipsToBounds = false
            view.addSubview(host)
        } else {
            isSupported = false
        }
    }

    func setColor(_ color: Color) {
        if state.color != color { state.color = color }
    }

    func setLights(_ lights: [GlassLight]) {
        let bounded = Array(lights.prefix(GlassLight.maximumCount))
        if state.lights != bounded { state.lights = bounded }
    }

    /// apply removes the glass subtree when idle or inaccessible, so the resting
    /// hardware notch never keeps a backdrop effect alive. Equal paths do not
    /// invalidate SwiftUI when the controller reapplies an unchanged frame.
    func apply(
        path        : CGPath,
        canvasBounds: CGRect,
        progress    : CGFloat,
        isVisible   : Bool
    ) {
        let isVisible = isSupported && isVisible
        view.isHidden = !isVisible
        guard isVisible else {
            if state.outline != nil { state.outline = nil }
            return
        }
        if view.frame != canvasBounds { view.frame = canvasBounds }
        if state.progress != progress { state.progress = progress }
        if state.outline != path { state.outline = path }
    }
}

/// NotchGlassState publishes only material inputs; it owns no clock or observer.
@Observable
@MainActor
private final class NotchGlassState {
    var outline: CGPath?
    var color: Color = .black
    var progress: CGFloat = 0
    var lights: [GlassLight] = []
}

/// NotchGlassShape translates the existing AppKit path into a local SwiftUI
/// surface. Sharing the outline keeps the visible glass and hit testing aligned.
nonisolated struct NotchGlassShape: Shape {
    private let outline: Path

    init(outline: CGPath) {
        self.outline = Path(outline)
    }

    nonisolated func path(in rect: CGRect) -> Path {
        let bounds = outline.boundingRect
        return outline.applying(CGAffineTransform(
            a : 1,
            b : 0,
            c : 0,
            d : -1,
            tx: rect.minX - bounds.minX,
            ty: rect.minY + bounds.maxY
        ))
    }
}

/// NotchGlassSurface uses the reference's dark-to-clear mesh inside clear glass.
/// The tint releases as the notch opens, while the top stays dark against the
/// camera cutout. AppKit/SwiftUI own backdrop sampling; no screen capture is used.
@available(macOS 26, *)
private struct NotchGlassSurface: View {
    let state: NotchGlassState

    var body: some View {
        GeometryReader { canvas in
            if let outline = state.outline {
                let bounds = outline.boundingBoxOfPath
                let shape = NotchGlassShape(outline: outline)
                let reveal = min(1, max(0, (state.progress - 0.3) / 0.7))

                ZStack {
                    NotchGlassLightField(lights: state.lights)
                        .opacity(reveal)
                        .clipShape(shape)
                    shape
                    .fill(MeshGradient(
                        width : 3,
                        height: 3,
                        points: [
                            [0, 0], [0.5, 0], [1, 0],
                            [0, 0.43], [0.5, 0.43], [1, 0.43],
                            [0, 1], [0.5, 1], [1, 1]
                        ],
                        colors: [
                            state.color, state.color, state.color,
                            state.color.opacity(0.65), state.color.opacity(0.65), state.color.opacity(0.65),
                            state.color.opacity(0.25), state.color.opacity(0.25), state.color.opacity(0.25)
                        ]
                    ))
                    .glassEffect(
                        .clear.tint(state.color.opacity(1 - 0.95 * reveal)),
                        in: shape
                    )
                }
                    .frame(width: bounds.width, height: bounds.height)
                    .position(x: bounds.midX, y: canvas.size.height - bounds.midY)
            }
        }
        .environment(\.colorScheme, .dark)
        .transaction { $0.animation = nil }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// PassiveNotchGlassView never intercepts the controls hosted above the material.
@MainActor
private final class PassiveNotchGlassView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
