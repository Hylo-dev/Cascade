//
//  CGRectSegmentTests.swift
//  CascadeKitTests
//

import Testing
import CoreGraphics
@testable import CascadeKit

/// The segment test is what makes a fast flick over the notch still open it, so
/// these pin down exactly that: a stroke that crosses the band counts as a hit
/// even when both endpoints are outside, while a stroke that misses does not.
struct CGRectSegmentTests {

    private let zone = CGRect(x: 100, y: 100, width: 50, height: 20) // x:100…150, y:100…120

    @Test
    func fastHorizontalFlightAcrossTheBandHits() {
        // Both endpoints outside (left and right), but the path crosses the band.
        #expect(zone.intersects(segmentFrom: CGPoint(x: 0, y: 110), to: CGPoint(x: 300, y: 110)))
    }

    @Test
    func fastVerticalFlightAcrossTheBandHits() {
        #expect(zone.intersects(segmentFrom: CGPoint(x: 120, y: 0), to: CGPoint(x: 120, y: 300)))
    }

    @Test
    func endpointInsideHits() {
        #expect(zone.intersects(segmentFrom: CGPoint(x: 125, y: 110), to: CGPoint(x: 500, y: 110)))
    }

    @Test
    func strokeThatMissesDoesNotHit() {
        // Parallel to the band but well above it.
        #expect(!zone.intersects(segmentFrom: CGPoint(x: 0, y: 200), to: CGPoint(x: 300, y: 200)))
    }

    @Test
    func strokeEntirelyToOneSideDoesNotHit() {
        #expect(!zone.intersects(segmentFrom: CGPoint(x: 0, y: 0), to: CGPoint(x: 10, y: 10)))
    }

    @Test
    func zeroLengthSegmentIsAPointTest() {
        #expect(zone.intersects(segmentFrom: CGPoint(x: 125, y: 110), to: CGPoint(x: 125, y: 110)))
        #expect(!zone.intersects(segmentFrom: CGPoint(x: 0, y: 0), to: CGPoint(x: 0, y: 0)))
    }
}
