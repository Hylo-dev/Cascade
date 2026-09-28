//
//  SpotlightDropletTimeline.swift
//  Cascade
//

import CoreGraphics
import Foundation

/// SpotlightDropletFrame contains allocation-free geometry for the two native glass surfaces.
nonisolated struct SpotlightDropletFrame: Equatable {
    let dropletBounds : CGRect
    let sourceBounds  : CGRect
    let opacity       : CGFloat
    let sourceOpacity : CGFloat
    let mergeSpacing  : CGFloat
    let cornerRadius  : CGFloat
    let isDetached    : Bool
    let isComplete    : Bool
}

/// SpotlightDropletTimeline gathers, detaches and finally widens a single glass drop.
///
/// Expansion is a distinct phase: at its first frame the surfaces are already
/// 36 points apart, beyond the container's final 22-point merge distance. This
/// makes detachment visible before the capsule starts resembling a search field.
nonisolated struct SpotlightDropletTimeline {
    let layout        : SpotlightDropletLayout
    let reducesMotion : Bool
    let duration      : Double
    let mergeSpacing  : CGFloat = 44

    init(
        layout        : SpotlightDropletLayout,
        reducesMotion : Bool
    ) {
        self.layout        = layout
        self.reducesMotion = reducesMotion
        self.duration      = reducesMotion ? 0.080 : 0.400
    }

    /// frame samples bounded value math without AppKit, AX, allocations or mutable state.
    func frame(at elapsed: Double) -> SpotlightDropletFrame {
        let time = elapsed.isNaN ? 0 : min(duration, max(0, elapsed))
        let bounds: CGRect

        if reducesMotion || time >= duration {
            bounds = layout.landingBounds
        } else if time <= 0.070 {
            let progress = Self.smoothProgress(time / 0.070)
            bounds = dropBounds(
                width  : Self.interpolate(44, 60, progress),
                height : Self.interpolate(22, 42, progress),
                top    : layout.hardwareNotchBounds.minY + Self.interpolate(20, 6, progress)
            )
        } else if time <= 0.180 {
            let progress = Self.smoothProgress((time - 0.070) / 0.110)
            bounds = dropBounds(
                width  : 60,
                height : Self.interpolate(42, min(64, layout.landingBounds.height), progress),
                top    : Self.interpolate(
                    layout.hardwareNotchBounds.minY + 6,
                    layout.landingBounds.maxY,
                    progress
                )
            )
        } else {
            let progress = Self.smoothProgress((time - 0.180) / 0.220)
            bounds = dropBounds(
                width  : Self.interpolate(60, layout.landingBounds.width, progress),
                height : Self.interpolate(min(64, layout.landingBounds.height), layout.landingBounds.height, progress),
                top    : layout.landingBounds.maxY
            )
        }

        // Keep a visible neck during descent, then release the proximity field
        // before horizontal expansion. A constant large spacing reconnects the
        // wide capsule; a constant small spacing pinches off too early.
        let currentSpacing = Self.interpolate(mergeSpacing, 22,
            Self.smoothProgress((time - 0.130) / 0.050))
        return SpotlightDropletFrame(
            dropletBounds : bounds,
            sourceBounds  : layout.sourceBounds,
            opacity       : Self.smoothProgress(time / 0.080),
            sourceOpacity : reducesMotion ? 0 : 1,
            mergeSpacing  : currentSpacing,
            cornerRadius  : min(bounds.width, bounds.height) / 2,
            isDetached    : reducesMotion || layout.sourceBounds.minY - bounds.maxY > currentSpacing,
            isComplete    : time >= duration
        )
    }

    /// dropBounds keeps the two surfaces on the hardware notch's centerline.
    private func dropBounds(
        width  : CGFloat,
        height : CGFloat,
        top    : CGFloat
    ) -> CGRect {
        CGRect(
            x      : layout.landingBounds.midX - width / 2,
            y      : top - height,
            width  : width,
            height : height
        )
    }

    /// smoothProgress keeps phase boundaries continuous and settles without spring overshoot.
    private static func smoothProgress(_ progress: Double) -> CGFloat {
        let clamped = min(1, max(0, progress))
        return CGFloat(clamped * clamped * (3 - 2 * clamped))
    }

    private static func interpolate(
        _ start    : CGFloat,
        _ end      : CGFloat,
        _ progress : CGFloat
    ) -> CGFloat {
        start + (end - start) * progress
    }
}
