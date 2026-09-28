//
//  CGPath+NotchDroplet.swift
//  CascadeKit
//

import CoreGraphics

extension CGPath {

    /// notchDroplet joins the satellite to the moving side with a concave neck.
    /// Boolean union removes interior seams from the shared border and hit path.
    /// Once the drop is absorbed, the ordinary notch path needs no extra work.
    static func notchDroplet(
        notch     : CGPath,
        rightEdge : CGFloat,
        bubble    : CGRect,
        attachment: CGFloat
    ) -> CGPath {
        guard bubble.width > 0.1, bubble.height > 0.1 else { return notch }

        let circle = CGPath(ellipseIn: bubble, transform: nil)

        guard attachment > 0, bubble.maxX > rightEdge else {
            guard attachment == 0 else { return notch }

            // A boolean union is a polygon clip on every frame of the bubble's
            // spring. While the drop is clear of the notch's bounds the two
            // shapes cannot share a seam, so adding the circle as a second
            // subpath fills, masks and hit-tests identically for a copy.
            guard notch.boundingBoxOfPath.intersects(bubble) else {
                let combined = CGMutablePath()
                combined.addPath(notch)
                combined.addPath(circle)

                return combined
            }

            return notch.union(circle)
        }

        let radius   = bubble.height / 2
        let reach    = min(1, attachment * 6)
        let halfNeck = radius * reach * 0.72
        let left     = rightEdge - 2
        let right    = max(left, bubble.midX)
        let control  = (left + right) / 2
        let centerY  = bubble.midY

        let neck = CGMutablePath()

        neck.move(to: CGPoint(x: left, y: centerY + radius))

        neck.addCurve(
            to      : CGPoint(x: right, y: centerY + halfNeck),
            control1: CGPoint(x: control, y: centerY + halfNeck * 0.2),
            control2: CGPoint(x: control, y: centerY + halfNeck * 0.2)
        )

        neck.addLine(to: CGPoint(x: right, y: centerY - halfNeck))

        neck.addCurve(
            to      : CGPoint(x: left, y: centerY - radius),
            control1: CGPoint(x: control, y: centerY - halfNeck * 0.2),
            control2: CGPoint(x: control, y: centerY - halfNeck * 0.2)
        )

        neck.closeSubpath()

        return notch.union(circle).union(neck)
    }
}
