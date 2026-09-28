//
//  NotchGeometry.swift
//  CascadeKit
//

import CoreGraphics

/// NotchGeometry holds the resolved shape of a single morph frame.
///
/// The notch can open asymmetrically — only the leading side, only the
/// trailing, or both — so the half-widths to the left and right of center are
/// independent. The struct carries no behavior, only the numbers the shape
/// layer turns into a `CGPath`. It is a small value type the morph loop reads on
/// every frame, so it stays cheap to copy and compare.
nonisolated struct NotchGeometry: Equatable, Sendable {

    let leftExtent        : CGFloat // Half-width left of center.
    let rightExtent       : CGFloat // Half-width right of center.
    let height            : CGFloat // How far the notch hangs down from the top edge.
    let bottomCornerRadius: CGFloat // Convex radius of the two bottom corners.
    let topCornerRadius   : CGFloat // Concave (inverted) radius where the top meets the screen edge.

    /// width is the total horizontal span, derived from the two extents rather
    /// than stored, so it can never disagree with sides that morph independently.
    var width: CGFloat { leftExtent + rightExtent }

    /// resolve computes the geometry for the current morph progress of each side.
    ///
    /// `leadingProgress` / `trailingProgress` are the springs' normalized
    /// outputs in `[0, 1]`: 0 hugs the resting notch, 1 is fully expanded. We
    /// interpolate each side independently from the resting half-width to the
    /// configured expanded half-width. `resolvedHeight` lets the controller run
    /// adaptive activity height on its own spring; callers that omit it retain
    /// the original normalized side-driven height interpolation.
    static func resolve(
        configuration           : NotchConfiguration,
        restingHalfWidth        : CGFloat,
        restingHeight           : CGFloat,
        compactLeadingExtension : CGFloat = 0,
        compactTrailingExtension: CGFloat = 0,
        compactCenterHalfWidth  : CGFloat? = nil,
        compactProgress         : CGFloat = 0,
        expandedHalfWidth       : CGFloat? = nil,
        resolvedHeight          : CGFloat? = nil,
        leadingProgress         : CGFloat,
        trailingProgress        : CGFloat
    ) -> NotchGeometry {

        let boundedCompactProgress = min(1, max(0, compactProgress))
        let compactHalfWidth = compactCenterHalfWidth ?? restingHalfWidth
        let resolvedCenterHalfWidth = restingHalfWidth
            + (compactHalfWidth - restingHalfWidth) * boundedCompactProgress
        let leadingRest  = resolvedCenterHalfWidth + compactLeadingExtension
        let trailingRest = resolvedCenterHalfWidth + compactTrailingExtension
        let expandedWidth = expandedHalfWidth ?? configuration.expandedHalfWidth
        let leftExtent = leadingRest + (expandedWidth - leadingRest) * leadingProgress
        let rightExtent = trailingRest + (expandedWidth - trailingRest) * trailingProgress

        let openness = max(leadingProgress, trailingProgress)
        let height = resolvedHeight
            ?? restingHeight + (configuration.expandedHeight - restingHeight) * openness

        // Round the continuous corners ahead of the size change, then retain
        // that softness on the way back to the hardware. Clamping only this
        // curve keeps the opening overshoot without reversing the roundness.
        let cornerProgress = min(1, max(0, openness))
        let roundness = cornerProgress * (2 - cornerProgress)
        let bottomCornerRadius = configuration.restingBottomCornerRadius
            + (configuration.expandedBottomCornerRadius - configuration.restingBottomCornerRadius) * roundness

        let topCornerRadius = configuration.restingTopCornerRadius
            + (configuration.expandedTopCornerRadius - configuration.restingTopCornerRadius) * roundness

        return NotchGeometry(
            leftExtent        : leftExtent,
            rightExtent       : rightExtent,
            height            : height,
            bottomCornerRadius: bottomCornerRadius,
            topCornerRadius   : topCornerRadius
        )
    }
}
