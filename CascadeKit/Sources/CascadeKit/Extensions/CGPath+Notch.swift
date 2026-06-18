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
/// hanging down from `topY`. The path is rebuilt each morph frame; it is a dozen
/// cheap segments and one small `CGPath` allocation, which is well within budget.
extension CGPath {

    /// Build the notch outline for `geometry`, horizontally centered on
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

        // Top-right concave corner: curve from the flared top down to the side.
        path.addArc(
            center    : CGPoint(x: right + topR, y: top - topR),
            radius    : topR,
            startAngle: .pi / 2,
            endAngle  : .pi,
            clockwise : false
        )

        path.addLine(to: CGPoint(x: right, y: bottom + bottomR))

        // Bottom-right convex corner.
        path.addArc(
            center    : CGPoint(x: right - bottomR, y: bottom + bottomR),
            radius    : bottomR,
            startAngle: 0,
            endAngle  : -.pi / 2,
            clockwise : true
        )

        path.addLine(to: CGPoint(x: left + bottomR, y: bottom))

        // Bottom-left convex corner.
        path.addArc(
            center    : CGPoint(x: left + bottomR, y: bottom + bottomR),
            radius    : bottomR,
            startAngle: -.pi / 2,
            endAngle  : .pi,
            clockwise : true
        )

        path.addLine(to: CGPoint(x: left, y: top - topR))

        // Top-left concave corner: curve from the side back up to the flared top.
        path.addArc(
            center    : CGPoint(x: left - topR, y: top - topR),
            radius    : topR,
            startAngle: 0,
            endAngle  : .pi / 2,
            clockwise : false
        )

        path.closeSubpath()

        return path.copy() ?? path
    }
}
