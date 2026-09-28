//
//  ContinuousNotchCorner.swift
//  CascadeKit
//

import CoreGraphics
import SwiftUI

/// ContinuousNotchCorner caches a native Apple continuous corner, normalized
/// from (0, 1) to (1, 0). Reflections turn it into either a convex or concave
/// notch corner without approximating the profile with a circular arc.
///
/// Apple's nominal corner radius reaches farther along the straight edges than
/// that radius. Normalizing the complete span preserves Cascade's existing
/// geometry/bounds contract; it does not claim a formula for Apple's private
/// radius calibration. A generously sized source rectangle keeps neighboring
/// corners from compressing this canonical profile.
/// https://developer.apple.com/documentation/swiftui/roundedcornerstyle/continuous
enum ContinuousNotchCorner {

    private static let profile  = makeProfile()
    private static let segments = profile.segments

    /// spanPerRadius is how far a native continuous corner of nominal radius 1
    /// reaches along each edge. A native view drawing its own continuous
    /// corners, such as NSGlassEffectView, matches this profile at span `s`
    /// when given the nominal radius `s / spanPerRadius`.
    static let spanPerRadius = profile.span

    /// append adds the cached corner to the current contour. Only CGPoint
    /// transforms and Core Graphics emission run on each morph frame; SwiftUI
    /// path construction and the small contiguous allocation happen once.
    static func append(
        to path  : CGMutablePath,
        transform: CGAffineTransform
    ) {
        for segment in segments {
            path.addCurve(
                to      : segment.end.applying(transform),
                control1: segment.control1.applying(transform),
                control2: segment.control2.applying(transform)
            )
        }
    }

    /// makeProfile extracts the lower-left quarter by coordinates instead of
    /// relying on a private element count or the contour's starting element.
    /// Path.forEach copies its values, so no borrowed CGPath pointers escape.
    private static func makeProfile() -> (segments: ContiguousArray<CubicSegment>, span: CGFloat) {
        let nativePath = RoundedRectangle(
            cornerRadius: 1,
            style       : .continuous
        ).path(in: CGRect(
            x     : 0,
            y     : 0,
            width : 10,
            height: 10
        ))

        var nativeSegments = ContiguousArray<CubicSegment>()
        var currentPoint   = CGPoint.zero
        nativeSegments.reserveCapacity(3)

        nativePath.forEach { element in
            let segment: CubicSegment
            switch element {
                case let .move(to: point):
                    currentPoint = point
                    return

                case let .line(to: point):
                    segment = CubicSegment(
                        start   : currentPoint,
                        control1: interpolate(
                            from    : currentPoint,
                            to      : point,
                            fraction: 1 / 3
                        ),
                        control2: interpolate(
                            from    : currentPoint,
                            to      : point,
                            fraction: 2 / 3
                        ),
                        end     : point
                    )

                case let .quadCurve(to: point, control: control):
                    segment = CubicSegment(
                        start   : currentPoint,
                        control1: interpolate(
                            from    : currentPoint,
                            to      : control,
                            fraction: 2 / 3
                        ),
                        control2: interpolate(
                            from    : point,
                            to      : control,
                            fraction: 2 / 3
                        ),
                        end     : point
                    )

                case let .curve(to: point, control1: first, control2: second):
                    segment = CubicSegment(
                        start   : currentPoint,
                        control1: first,
                        control2: second,
                        end     : point
                    )

                case .closeSubpath:
                    return
            }

            currentPoint = segment.end
            if segment.start.x < 5 && segment.start.y < 5
                && segment.end.x < 5 && segment.end.y < 5 {
                nativeSegments.append(segment)
            }
        }

        // The native representation must expose the rounded quarter before it
        // can be reused. Validate this extraction once, never in the morph loop.
        guard let first = nativeSegments.first, let last = nativeSegments.last else {
            preconditionFailure("A native continuous rounded rectangle must contain a corner.")
        }

        let span  = max(first.start.x, first.start.y, last.end.x, last.end.y)
        let scale = CGAffineTransform(scaleX: 1 / span, y: 1 / span)

        // Normalize direction as well: the outline can begin on any edge and
        // a future native renderer may reverse its winding direction.
        if first.start.x > first.start.y {
            return (ContiguousArray(nativeSegments.reversed().map { segment in
                CubicSegment(
                    start   : segment.end.applying(scale),
                    control1: segment.control2.applying(scale),
                    control2: segment.control1.applying(scale),
                    end     : segment.start.applying(scale)
                )
            }), span)
        }

        return (ContiguousArray(nativeSegments.map { segment in
            CubicSegment(
                start   : segment.start.applying(scale),
                control1: segment.control1.applying(scale),
                control2: segment.control2.applying(scale),
                end     : segment.end.applying(scale)
            )
        }), span)
    }

    /// interpolate elevates line/quadratic segments to cubics during cache
    /// construction if a future native implementation changes its primitives.
    private static func interpolate(
        from start: CGPoint,
        to end    : CGPoint,
        fraction  : CGFloat
    ) -> CGPoint {
        CGPoint(
            x: start.x + (end.x - start.x) * fraction,
            y: start.y + (end.y - start.y) * fraction
        )
    }

    /// CubicSegment owns the copied control points of one native path segment.
    private struct CubicSegment {

        let start   : CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end     : CGPoint
    }
}
