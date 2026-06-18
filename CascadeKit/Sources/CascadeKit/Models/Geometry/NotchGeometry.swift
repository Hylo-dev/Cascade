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

    /// Total horizontal span of the notch.
    var width: CGFloat { leftExtent + rightExtent }

    /// Resolve the geometry for the current morph progress of each side.
    ///
    /// `leadingProgress` / `trailingProgress` are the springs' normalized
    /// outputs in `[0, 1]`: 0 hugs the resting notch, 1 is fully expanded. We
    /// interpolate each side independently from the resting half-width to the
    /// configured expanded half-width, and grow the height by whichever side is
    /// more open so the shape never clips its taller content.
    static func resolve(
        configuration   : NotchConfiguration,
        restingHalfWidth: CGFloat,
        restingHeight   : CGFloat,
        leadingProgress : CGFloat,
        trailingProgress: CGFloat
    ) -> NotchGeometry {

        let reach       = configuration.expandedHalfWidth - restingHalfWidth
        let leftExtent  = restingHalfWidth + reach * leadingProgress
        let rightExtent = restingHalfWidth + reach * trailingProgress

        let openness    = max(leadingProgress, trailingProgress)
        let height      = restingHeight + (configuration.expandedHeight - restingHeight) * openness

        // The corner radii morph from the resting set to the expanded set on the
        // same `openness` curve as the height, so the closed pill and the open
        // island can carry completely different roundness.
        let bottomCornerRadius = configuration.restingBottomCornerRadius
            + (configuration.expandedBottomCornerRadius - configuration.restingBottomCornerRadius) * openness

        let topCornerRadius = configuration.restingTopCornerRadius
            + (configuration.expandedTopCornerRadius - configuration.restingTopCornerRadius) * openness

        return NotchGeometry(
            leftExtent        : leftExtent,
            rightExtent       : rightExtent,
            height            : height,
            bottomCornerRadius: bottomCornerRadius,
            topCornerRadius   : topCornerRadius
        )
    }
}
