//
//  NotchLayoutResolverTests.swift
//  CascadeKitTests
//

import Testing
import CoreGraphics
@testable import CascadeKit

/// The resolver is pure math, so it's the part we can pin down hard: cells map
/// to the right rects, row 0 only offers the trailing side of the notch, the
/// two main rows are fully usable, oversized placements are dropped, and a
/// narrow notch degrades the trailing-cell count (the "does it fit" answer).
struct NotchLayoutResolverTests {

    private let resolver = NotchLayoutResolver() // .default metrics: 14 cols, gutter 6, ≤4 trailing
    private let interior = CGRect(x: 0, y: 0, width: 640, height: 180)
    private let notchWidth   : CGFloat = 200
    private let topBandHeight: CGFloat = 36

    private func resolve(_ placements: [WidgetIdentifier: WidgetPlacement]) -> NotchLayout {
        resolver.resolve(
            interior     : interior,
            notchWidth   : notchWidth,
            topBandHeight: topBandHeight,
            placements   : placements
        )
    }

    @Test
    func computesNotchColumnsAndTrailingFit() {
        let layout = resolve([:])
        #expect(layout.notchColumns == 5)       // 200pt over ~46pt columns
        #expect(layout.trailingCellCount == 4)  // fits the configured maximum
    }

    @Test
    func smallWidgetMapsToOneMainCell() throws {

        let id     = WidgetIdentifier("small")
        let layout = resolve([
            id: WidgetPlacement(position: GridPosition(column: 0, row: 1), span: .small)
        ])

        let frame = try #require(layout.frames[id])
        #expect(abs(frame.minX  - 0)          < 0.01)
        #expect(abs(frame.width - 40.142857)  < 0.1)  // (640 - 6×13) / 14
        #expect(abs(frame.minY  - 72)         < 0.1)  // below the band + gutter
        #expect(abs(frame.height - 66)        < 0.1)  // one main row
    }

    @Test
    func largeWidgetSpansBothMainRows() throws {

        let id     = WidgetIdentifier("large")
        let layout = resolve([
            id: WidgetPlacement(position: GridPosition(column: 2, row: 1), span: GridSpan(columns: 3, rows: 2))
        ])

        let frame = try #require(layout.frames[id])
        #expect(abs(frame.minY   - 0)   < 0.1)  // reaches the bottom (row 2)
        #expect(abs(frame.height - 138) < 0.1)  // two main rows + the gutter between
    }

    @Test
    func row0OffersOnlyTheTrailingSide() {

        let trailing = WidgetIdentifier("trailing")
        let slider   = WidgetIdentifier("slider")

        let layout = resolve([
            trailing: WidgetPlacement(position: GridPosition(column: 9, row: 0), span: .small),
            slider  : WidgetPlacement(position: GridPosition(column: 0, row: 0), span: .small),
        ])

        #expect(layout.frames[trailing] != nil) // trailing side of the notch
        #expect(layout.frames[slider]   == nil) // slider / notch area is reserved
    }

    @Test
    func overflowingPlacementIsDropped() {

        let id     = WidgetIdentifier("overflow")
        let layout = resolve([
            id: WidgetPlacement(position: GridPosition(column: 13, row: 1), span: GridSpan(columns: 2, rows: 1))
        ])

        #expect(layout.frames[id] == nil) // columns 13,14 — column 14 is out of bounds
    }

    @Test
    func narrowNotchDegradesTrailingCells() {

        let layout = NotchLayoutResolver().resolve(
            interior     : CGRect(x: 0, y: 0, width: 300, height: 160),
            notchWidth   : 250,
            topBandHeight: 36,
            placements   : [:]
        )

        #expect(layout.trailingCellCount < 4) // a 250pt notch eats most of a 300pt band
    }
}
