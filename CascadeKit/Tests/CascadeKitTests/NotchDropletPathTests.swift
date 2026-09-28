//
//  NotchDropletPathTests.swift
//  CascadeKit
//

import CoreGraphics
import Testing
@testable import CascadeKit

struct NotchDropletPathTests {
    private let notch = CGPath.notch(
        geometry: NotchGeometry(leftExtent: 110, rightExtent: 110, height: 32, bottomCornerRadius: 14, topCornerRadius: 4),
        centerX : 300,
        topY    : 200
    )

    /// A detached bubble must cover exactly what a boolean union covers, so the
    /// cheaper composition cannot change fill, mask or hit testing.
    @Test(arguments: [
        CGRect(x: 430, y: 170, width: 26, height: 26),   // clear of the notch
        CGRect(x: 395, y: 172, width: 26, height: 26),   // overlapping its side
        CGRect(x: 405, y: 150, width: 26, height: 26),   // near its lower corner
    ])
    func detachedBubbleCoversTheSameRegionAsAUnion(bubble: CGRect) {
        let droplet = CGPath.notchDroplet(notch: notch, rightEdge: 410, bubble: bubble, attachment: 0)
        let reference = notch.union(CGPath(ellipseIn: bubble, transform: nil))
        let region = notch.boundingBoxOfPath.union(bubble).insetBy(dx: -6, dy: -6)
        var mismatches = 0
        for x in stride(from: region.minX, through: region.maxX, by: 1.5) {
            for y in stride(from: region.minY, through: region.maxY, by: 1.5) {
                let point = CGPoint(x: x, y: y)
                if droplet.contains(point) != reference.contains(point) { mismatches += 1 }
            }
        }
        #expect(mismatches == 0)
    }
}
