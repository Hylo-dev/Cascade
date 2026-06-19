//
//  CGRect+Segment.swift
//  CascadeKit
//

import CoreGraphics

/// CGRect + segment intersection.
///
/// Hover detection samples the pointer at a finite rate, so a fast flick can put
/// one sample to the left of the trigger band and the next to the right, with
/// none ever *inside* it. Testing the whole segment travelled between two
/// samples — instead of just the latest point — closes that gap: any path that
/// crosses the band counts as a hit, no matter how fast the mouse moved.
extension CGRect {

    /// Whether the line segment from `p0` to `p1` touches this rect (an endpoint
    /// inside counts as touching).
    ///
    /// Uses Liang–Barsky clipping: it walks the segment's parameter `t ∈ [0, 1]`
    /// against the rect's four slabs, narrowing `[tEnter, tExit]`; the segment
    /// intersects iff that interval stays non-empty. It is branch-light and
    /// allocation-free — safe to call on every (throttled) pointer event.
    func intersects(
        segmentFrom p0: CGPoint,
        to          p1: CGPoint
    ) -> Bool {

        let dx = p1.x - p0.x
        let dy = p1.y - p0.y

        // A zero-length segment is just a point.
        if dx == 0, dy == 0 {
            return contains(p0)
        }

        var tEnter: CGFloat = 0
        var tExit : CGFloat = 1

        // One Liang–Barsky slab. `p` is the edge's outward rate along the
        // segment, `q` the signed distance of `p0` from that edge. Returns false
        // the moment the segment is ruled out; otherwise narrows the interval.
        func clip(
            p: CGFloat,
            q: CGFloat
        ) -> Bool {

            if p == 0 {
                return q >= 0 // Parallel to the edge: inside it iff q >= 0.
            }

            let t = q / p

            if p < 0 {
                tEnter = max(tEnter, t)
            } else {
                tExit = min(tExit, t)
            }

            return true
        }

        guard clip(p: -dx, q: p0.x - minX) else { return false } // Left.
        guard clip(p:  dx, q: maxX - p0.x) else { return false } // Right.
        guard clip(p: -dy, q: p0.y - minY) else { return false } // Bottom.
        guard clip(p:  dy, q: maxY - p0.y) else { return false } // Top.

        return tEnter <= tExit
    }
}
