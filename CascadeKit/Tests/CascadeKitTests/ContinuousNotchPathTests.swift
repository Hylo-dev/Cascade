//
//  ContinuousNotchPathTests.swift
//  CascadeKit
//

import CoreGraphics
import SwiftUI
import Testing
@testable import CascadeKit

/// ContinuousNotchPathTests protects the bezel attachment and the smooth
/// transition from each straight edge into Apple's continuous corner profile.
@MainActor
struct ContinuousNotchPathTests {

    @Test
    func bottomCornersUseTheFullerContinuousProfile() {
        let path = makePath()

        // At one fifth of both corner spans, a circular corner still excludes
        // this point. Apple's continuous profile reaches closer to the vertex.
        #expect(path.contains(CGPoint(x: -96, y: 4)))
        #expect(path.contains(CGPoint(x: 96, y: 4)))
    }

    @Test
    func topCornersReflectTheContinuousProfileIntoTheBezel() {
        let path = makePath()

        #expect(!path.contains(CGPoint(x: -104, y: 76)))
        #expect(!path.contains(CGPoint(x: 104, y: 76)))
        #expect(path.contains(CGPoint(x: -101, y: 79)))
        #expect(path.contains(CGPoint(x: 101, y: 79)))
    }

    @Test
    func allFourCornersMatchTheNormalizedNativeAppleProfile() throws {
        let native = RoundedRectangle(
            cornerRadius: 1,
            style       : .continuous
        ).path(in: CGRect(x: 0, y: 0, width: 10, height: 10)).cgPath
        let nativeCorner = try #require(curveGroups(in: native).first { group in
            group.first?.start.x == 0 && group.last?.end.y == 0
        })
        let nativeSpan = try #require(nativeCorner.first?.start.y)
        let path = makePath()

        // Compare filled regions against the complete native shape, including
        // the complemented region that becomes each concave bezel attachment.
        // Samples stay off the axes so Core Graphics boundary inclusion does
        // not become part of the contract.
        for horizontal in stride(from: CGFloat(0.025), through: 0.975, by: 0.05) {
            for vertical in stride(from: CGFloat(0.025), through: 0.975, by: 0.05) {
                let nativeContains = native.contains(CGPoint(
                    x: horizontal * nativeSpan,
                    y: vertical * nativeSpan
                ))
                #expect(path.contains(CGPoint(x: -100 + horizontal * 20, y: vertical * 20))
                    == nativeContains)
                #expect(path.contains(CGPoint(x: 100 - horizontal * 20, y: vertical * 20))
                    == nativeContains)
                #expect(path.contains(CGPoint(x: 100 + vertical * 20, y: 80 - horizontal * 20))
                    != nativeContains)
                #expect(path.contains(CGPoint(x: -100 - horizontal * 20, y: 80 - vertical * 20))
                    != nativeContains)
            }
        }
    }

    @Test
    func cornerCurvatureStartsAndEndsAtZeroAgainstTheStraightEdges() {
        let groups = curveGroups(in: makePath())
        #expect(groups.count == 4)

        for group in groups {
            guard let first = group.first, let last = group.last else {
                Issue.record("Every corner must contain a curve.")
                continue
            }

            // Three collinear endpoint/control points make a cubic's normal
            // acceleration zero at the line join. A circular arc fails here.
            #expect(abs(crossProduct(
                origin: first.start,
                first : first.control1,
                second: first.control2
            )) < 0.000001)
            #expect(abs(crossProduct(
                origin: last.end,
                first : last.control2,
                second: last.control1
            )) < 0.000001)
        }
    }

    @Test
    func asymmetricExtentsPreserveBoundsAndTheTopAttachment() {
        let path = CGPath.notch(
            geometry: NotchGeometry(
                leftExtent        : 70,
                rightExtent       : 130,
                height            : 80,
                bottomCornerRadius: 20,
                topCornerRadius   : 12
            ),
            centerX : 300,
            topY    : 500
        )

        #expect(path.boundingBoxOfPath == CGRect(x: 218, y: 420, width: 224, height: 80))
        #expect(path.contains(CGPoint(x: 220, y: 499.999)))
        #expect(path.contains(CGPoint(x: 440, y: 499.999)))
        #expect(!path.contains(CGPoint(x: 300, y: 500.001)))
    }

    @Test
    func leftAndRightProfilesMirrorAcrossTheGeometricMidpoint() {
        let path = makePath()

        for horizontal in stride(from: CGFloat(80.5), through: 120, by: 1) {
            for vertical in stride(from: CGFloat(0.5), through: 80, by: 1) {
                #expect(path.contains(CGPoint(x: horizontal, y: vertical))
                    == path.contains(CGPoint(x: -horizontal, y: vertical)))
            }
        }
    }

    @Test
    func zeroRadiiProduceTheExactRectangularOutline() {
        let path = makePath(
            width : 200,
            height: 80,
            radius: 0
        )

        #expect(path.boundingBoxOfPath == CGRect(x: -100, y: 0, width: 200, height: 80))
        #expect(path.contains(CGPoint(x: -99.999, y: 0.001)))
        #expect(path.contains(CGPoint(x: 99.999, y: 79.999)))
        #expect(!path.contains(CGPoint(x: 100.001, y: 40)))
    }

    @Test
    func oversizedRadiiRemainFiniteAndInsideTheClampedEnvelope() {
        let path = makePath(
            width : 3,
            height: 2,
            radius: 100
        )

        #expect(path.boundingBoxOfPath == CGRect(x: -2.5, y: 0, width: 5, height: 2))
        #expect(path.contains(CGPoint(x: 0, y: 1)))

        for group in curveGroups(in: path) {
            for curve in group {
                for point in [curve.start, curve.control1, curve.control2, curve.end] {
                    #expect(point.x.isFinite && point.y.isFinite)
                    #expect((-2.5...2.5).contains(point.x))
                    #expect((0...2).contains(point.y))
                }
            }
        }
    }

    @Test
    func collapsedGeometryDoesNotIntroduceNonfiniteControlPoints() {
        for size in [CGSize(width: 0, height: 80), CGSize(width: 200, height: 0), .zero] {
            let path = makePath(
                width : size.width,
                height: size.height,
                radius: 20
            )
            #expect(path.boundingBoxOfPath.width == size.width)
            #expect(path.boundingBoxOfPath.height == size.height)
            #expect(!path.contains(CGPoint(x: 0.1, y: 0.1)))

            for group in curveGroups(in: path) {
                for curve in group {
                    for point in [curve.start, curve.control1, curve.control2, curve.end] {
                        #expect(point.x.isFinite && point.y.isFinite)
                    }
                }
            }
        }
    }

    /// makePath places the lower edge at zero to make corner fixtures readable.
    private func makePath(
        width : CGFloat = 200,
        height: CGFloat = 80,
        radius: CGFloat = 20
    ) -> CGPath {
        CGPath.notch(
            geometry: NotchGeometry(
                leftExtent        : width / 2,
                rightExtent       : width / 2,
                height            : height,
                bottomCornerRadius: radius,
                topCornerRadius   : radius
            ),
            centerX : 0,
            topY    : height
        )
    }

    /// curveGroups separates corners at the straight edges of the outline.
    private func curveGroups(in path: CGPath) -> [[CubicCurve]] {
        var groups       = [[CubicCurve]]()
        var currentGroup = [CubicCurve]()
        var currentPoint = CGPoint.zero

        // CGPath owns the element storage for the duration of this callback.
        // The element type guarantees exactly three points for a cubic and one
        // for a move/line; only copied CGPoint values escape the callback.
        path.applyWithBlock { pointer in
            let element = pointer.pointee
            if element.type == .addCurveToPoint {
                currentGroup.append(CubicCurve(
                    start   : currentPoint,
                    control1: element.points[0],
                    control2: element.points[1],
                    end     : element.points[2]
                ))
                currentPoint = element.points[2]
            } else {
                if !currentGroup.isEmpty {
                    groups.append(currentGroup)
                    currentGroup.removeAll(keepingCapacity: true)
                }
                if element.type == .moveToPoint || element.type == .addLineToPoint {
                    currentPoint = element.points[0]
                }
            }
        }
        if !currentGroup.isEmpty {
            groups.append(currentGroup)
        }
        return groups
    }

    /// crossProduct detects normal acceleration at an endpoint without
    /// depending on the magnitude of the derivative or its coordinate axis.
    private func crossProduct(
        origin: CGPoint,
        first : CGPoint,
        second: CGPoint
    ) -> CGFloat {
        (first.x - origin.x) * (second.y - origin.y)
            - (first.y - origin.y) * (second.x - origin.x)
    }

    private struct CubicCurve {
        let start   : CGPoint
        let control1: CGPoint
        let control2: CGPoint
        let end     : CGPoint
    }
}
