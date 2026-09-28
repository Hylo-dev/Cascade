//
//  CGPath+Notch.swift
//  CascadeKit
//

import CoreGraphics

/// CGPath + the notch outline.
///
/// The notch hangs from the top edge of its host view, and its silhouette is the
/// reason it reads as *part of the screen* rather than a floating rectangle:
///
/// - The two **bottom** corners are **convex** (a normal rounded radius) — the
///   soft underside of the island.
/// - The two **top** corners are **concave** (an inverted radius): instead of a
///   square edge, the shape flares outward and curves back up to meet the very
///   top of the screen, so it looks carved into the bezel. Without this the
///   straight vertical sides read as visible "borders"; with it they melt into
///   the top edge.
///
/// Everything is in the host view's coordinates (y grows upward), with the notch
/// hanging down from `topY`. Both sets of corners use Apple's continuous
/// rounded-rectangle profile. Its normalized control points are cached once;
/// each morph frame only reflects/scales those points and creates one `CGPath`.
extension CGPath {

    /// notch builds the outline for `geometry`, horizontally centered on
    /// `centerX` and hanging down from `topY`.
    static func notch(
        geometry: NotchGeometry,
        centerX : CGFloat,
        topY    : CGFloat
    ) -> CGPath {

        let left   = centerX - geometry.leftExtent
        let right  = centerX + geometry.rightExtent
        let top    = topY
        let bottom = topY - geometry.height

        // Clamp the radii so they never exceed what the current size can hold —
        // when the notch is small (resting) a large radius would invert the path.
        let halfWidth = geometry.width / 2
        let bottomR   = max(0, min(geometry.bottomCornerRadius, geometry.height / 2, halfWidth))
        let topR      = max(0, min(geometry.topCornerRadius, geometry.height / 2, halfWidth))

        let path = CGMutablePath()

        // Start at the top-left, already flared out by `topR`, and trace
        // clockwise: across the top, down the right (concave corner), around the
        // convex bottom, and back up the left (concave corner).
        path.move(to: CGPoint(x: left - topR, y: top))

        path.addLine(to: CGPoint(x: right + topR, y: top))

        // Reflect the same native corner for both the concave bezel attachment
        // and the convex underside. The radius remains the corner's total span,
        // so switching profiles does not change layout bounds or hit regions.
        ContinuousNotchCorner.append(
            to       : path,
            transform: CGAffineTransform(
                a : 0,
                b : -topR,
                c : topR,
                d : 0,
                tx: right,
                ty: top
            )
        )

        path.addLine(to: CGPoint(x: right, y: bottom + bottomR))

        // Bottom-right convex corner.
        ContinuousNotchCorner.append(
            to       : path,
            transform: CGAffineTransform(
                a : -bottomR,
                b : 0,
                c : 0,
                d : bottomR,
                tx: right,
                ty: bottom
            )
        )

        path.addLine(to: CGPoint(x: left + bottomR, y: bottom))

        // Bottom-left convex corner.
        ContinuousNotchCorner.append(
            to       : path,
            transform: CGAffineTransform(
                a : 0,
                b : bottomR,
                c : bottomR,
                d : 0,
                tx: left,
                ty: bottom
            )
        )

        path.addLine(to: CGPoint(x: left, y: top - topR))

        // Top-left concave corner: curve from the side back up to the flared top.
        ContinuousNotchCorner.append(
            to       : path,
            transform: CGAffineTransform(
                a : -topR,
                b : 0,
                c : 0,
                d : -topR,
                tx: left,
                ty: top
            )
        )

        path.closeSubpath()

        // Return the mutable path directly: it's built fresh each frame and
        // never mutated after, and `CAShapeLayer.path` copies on assignment —
        // so an extra `.copy()` here would just be a wasted per-frame allocation.
        return path
    }
}
