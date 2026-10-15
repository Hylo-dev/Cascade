//
//  AudioVolumeGlassLightView.swift
//  CascadeKit
//

import AppKit
import CascadeContracts

/// AudioVolumeGlassLightView lights the notch's glass from a volume fill, so the capsule reads
/// as part of the notch: the light rises under the glass where the fill is and brightens as the
/// level does. The global volume lights it in its light blue, each app's capsule in its icon's
/// colour (`AudioGlassTint`), a little weaker. It draws nothing itself and takes no clicks.
///
/// It hands its light straight to the glass through `NotchGlassLightReceiving`, as the Music
/// cover does, because a drag changes the level on every pointer event and a SwiftUI preference
/// would re-evaluate the view tree each time. The level is quantized to `steps`, so a full sweep
/// moves the light at most that many times however fast the pointer reports, and an unchanged
/// step sends nothing. A silent level (zero, or muted) and Reduce Transparency withdraw the light.
/// The notch opening or closing moves the outline the light is placed on, so it hears that through
/// `NotchGlassLightEmitting` and places the light again.
@MainActor
final class AudioVolumeGlassLightView: NSView, NotchGlassLightEmitting {

    /// steps is how finely the light follows the level; the glass eases each move over a frame
    /// at 30 Hz, so a coarser step still reads as continuous.
    private static let steps = 32.0

    private let widthRatio: CGFloat

    /// strength scales the light: 1 for the global volume, less for the thin per-app capsules,
    /// which sit side by side and would otherwise flood the glass between them.
    private let strength: Double

    private weak var receiver: (any NotchGlassLightReceiving)?

    private var step      = 0.0
    private var isMuted   = false
    private var isEnabled = true
    private var tint      = AudioGlassTint.volume

    init(
        widthRatio: CGFloat,
        strength  : Double
    ) {
        self.widthRatio = widthRatio
        self.strength   = strength
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
        emit()
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
        level    : Double,
        isMuted  : Bool,
        isEnabled: Bool,
        tint     : AudioGlassTint
    ) {
        let step = (Swift.min(Swift.max(level, 0), 1) * Self.steps).rounded() / Self.steps
        guard
            step != self.step || isMuted != self.isMuted || isEnabled != self.isEnabled || tint != self.tint
        else { return }

        self.step      = step
        self.isMuted   = isMuted
        self.isEnabled = isEnabled
        self.tint      = tint
        emit()
    }

    func withdraw() {
        receiver?.setGlassLights([], from: self)
    }

    func glassLightBoundsDidChange() {
        emit()
    }

    /// emit places one light at the middle of the fill, in the receiver's normalized outline as
    /// every glass light is. The pill is measured with the capsule's own metrics, so the light
    /// sits on the pill that is drawn, not on the wider frame around it.
    private func emit() {
        guard let receiver, window != nil, isEnabled, !isMuted, step > 0 else {
            withdraw()
            return
        }

        let outline = receiver.glassLightBounds
        guard outline.width > 0, outline.height > 0 else { return }

        let metrics = AudioVolumeCapsuleMetrics(
            availableWidth : bounds.width,
            availableHeight: bounds.height,
            widthRatio     : widthRatio
        )
        let fillMiddle = metrics.height * CGFloat(step) / 2
        let pillBottom = isFlipped
            ? bounds.midY + metrics.height / 2
            : bounds.midY - metrics.height / 2
        let point      = CGPoint(
            x: bounds.midX,
            y: isFlipped ? pillBottom - fillMiddle : pillBottom + fillMiddle
        )

        let centre      = convert(point, to: receiver)
        let normalizedX = Swift.min(1, Swift.max(0, (centre.x - outline.minX) / outline.width))
        let normalizedY = Swift.min(1, Swift.max(0, (outline.maxY - centre.y) / outline.height))
        let radius      = metrics.width * (2.4 + CGFloat(step) * 1.2) / outline.width

        guard let light = try? GlassLight(
            x        : normalizedX,
            y        : normalizedY,
            radius   : Swift.min(1, Swift.max(0.01, radius)),
            red      : tint.red,
            green    : tint.green,
            blue     : tint.blue,
            intensity: Swift.min(1, (0.3 + 0.5 * step) * strength)
        ) else { return }

        receiver.setGlassLights([light], from: self)
    }
}
