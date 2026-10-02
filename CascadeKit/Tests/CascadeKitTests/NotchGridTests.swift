//
//  NotchGridTests.swift
//  CascadeKit
//

import CoreGraphics
import Foundation
import Testing
@testable import CascadeKit

/// NotchGridTests pins the editing rules down: what fits where, which band cells exist, and
/// where the first free fit lands, since every drop, resize and addition goes through them.
struct NotchGridTests {

    private let grid = NotchGrid(columns: 14, bandColumns: 10 ..< 14)

    private func placement(
        _ column: Int,
        _ row   : Int,
        _ span  : GridSpan
    ) -> WidgetPlacement {
        WidgetPlacement(position: GridPosition(column: column, row: row), span: span)
    }

    @Test
    func aFreeBlockInsideTheMainRowsFits() {
        #expect(grid.fits(placement(0, 1, GridSpan(columns: 4, rows: 2)), among: []))
        #expect(grid.fits(placement(10, 2, GridSpan(columns: 4, rows: 1)), among: []))
    }

    @Test
    func aBlockOutsideTheGridOrOverAnotherDoesNotFit() {
        let clock = placement(0, 1, GridSpan(columns: 4, rows: 2))

        #expect(!grid.fits(placement(12, 1, GridSpan(columns: 4, rows: 1)), among: []))
        #expect(!grid.fits(placement(0, 2, GridSpan(columns: 4, rows: 2)), among: []))
        #expect(!grid.fits(placement(3, 2, GridSpan(columns: 4, rows: 1)), among: [clock]))
        #expect(grid.fits(placement(4, 2, GridSpan(columns: 4, rows: 1)), among: [clock]))
    }

    @Test
    func theBandOffersOnlyItsTrailingCellsAndOnlyToOneRowWidgets() {
        #expect(grid.fits(placement(10, 0, GridSpan(columns: 4, rows: 1)), among: []))
        #expect(!grid.fits(placement(2, 0, .small), among: []))
        #expect(!grid.fits(placement(9, 0, GridSpan(columns: 2, rows: 1)), among: []))
        #expect(!grid.fits(placement(10, 0, GridSpan(columns: 4, rows: 2)), among: []))
    }

    @Test
    func theFirstFitSkipsTakenCellsAndPutsTallWidgetsOnTheFirstMainRow() {
        let clock = placement(0, 1, GridSpan(columns: 4, rows: 2))

        #expect(grid.firstFit(for: GridSpan(columns: 4, rows: 1), among: [clock]) == placement(4, 1, GridSpan(columns: 4, rows: 1)))
        #expect(grid.firstFit(for: GridSpan(columns: 4, rows: 2), among: [clock]) == placement(4, 1, GridSpan(columns: 4, rows: 2)))
        #expect(grid.firstFit(for: GridSpan(columns: 14, rows: 2), among: [clock]) == nil)
    }

    @Test
    func placementsOverlapOnlyWhenTheyShareACell() {
        let clock = placement(0, 1, GridSpan(columns: 4, rows: 2))

        #expect(clock.overlaps(placement(3, 2, .small)))
        #expect(!clock.overlaps(placement(4, 1, .small)))
        #expect(!clock.overlaps(placement(0, 0, .small)))
    }

    @Test
    func aDecodedSpanIsClampedAsTheInitializerClampsIt() throws {
        let data = Data(#"{"columns": 0, "rows": 5}"#.utf8)

        let span = try JSONDecoder().decode(GridSpan.self, from: data)

        #expect(span == GridSpan(columns: 1, rows: 2))
    }

    @Test
    func aPlacementSurvivesAnEncodingRoundTrip() throws {
        let original = placement(10, 0, GridSpan(columns: 4, rows: 1))

        let decoded = try JSONDecoder().decode(WidgetPlacement.self, from: JSONEncoder().encode(original))

        #expect(decoded == original)
    }
}
