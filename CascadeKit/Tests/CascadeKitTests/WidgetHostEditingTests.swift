//
//  WidgetHostEditingTests.swift
//  CascadeKit
//

import CoreGraphics
import Foundation
import Testing
@testable import CascadeKit

/// WidgetHostEditingTests covers the arrangement the user edits: one per display, starting from
/// the shared auto-placed default, with drops that refuse what does not fit, removals that
/// suspend the widget and offer it in the gallery, additions at the first free fit and resizes
/// that keep their place when they can.
@MainActor
struct WidgetHostEditingTests {

    private let grid      = NotchGrid(columns: 14, bandColumns: 10 ..< 14)
    private let builtIn   = DisplayIdentity(rawValue: "built-in")
    private let external  = DisplayIdentity(rawValue: "external")
    private let tall      = GridSpan(columns: 4, rows: 2)
    private let wide      = GridSpan(columns: 4, rows: 1)

    private func placement(
        _ column: Int,
        _ row   : Int,
        _ span  : GridSpan
    ) -> WidgetPlacement {
        WidgetPlacement(position: GridPosition(column: column, row: row), span: span)
    }

    /// host registers a clock and a battery, both 4×2 with a 4×1 alternative, and opens the
    /// built-in display's page.
    private func host() -> (WidgetHost, EditableWidgetFixture, EditableWidgetFixture) {
        let host    = WidgetHost()
        let clock   = EditableWidgetFixture("clock", sizes: [tall, wide])
        let battery = EditableWidgetFixture("battery", sizes: [wide, tall])
        host.register(clock)
        host.register(battery)
        host.update(state: .open, display: builtIn)

        return (host, clock, battery)
    }

    @Test
    func aDisplayNobodyEditedShowsTheAutoPlacedDefault() {
        let (host, clock, battery) = host()

        #expect(host.arrangement == [clock.id: placement(0, 1, tall), battery.id: placement(4, 1, wide)])
        #expect(clock.isActive && battery.isActive)
    }

    @Test
    func aDropOnAFreeFitMovesTheWidgetAndAnOccupiedOneIsRefused() {
        let (host, clock, battery) = host()

        let onBattery = host.move(clock.id, to: GridPosition(column: 2, row: 1), on: grid)
        let intoBand  = host.move(battery.id, to: GridPosition(column: 10, row: 0), on: grid)

        #expect(!onBattery)
        #expect(intoBand)
        #expect(host.arrangement == [clock.id: placement(0, 1, tall), battery.id: placement(10, 0, wide)])
    }

    @Test
    func aDropSnapsTheDraggedCornerToTheNearestCellOrIsRefused() throws {
        let (host, clock, battery) = host()
        let layout  = NotchLayoutResolver().resolve(
            interior     : CGRect(x: 0, y: 0, width: 640, height: 180),
            notchWidth   : 200,
            topBandHeight: 36,
            placements   : host.arrangement
        )
        let actions = host.actions(for: layout, setEditing: { _ in })
        let origin  = try #require(layout.cells[GridPosition(column: 0, row: 1)])
        let right   = try #require(layout.cells[GridPosition(column: 1, row: 1)]).minX - origin.minX
        let down    = origin.maxY - (try #require(layout.cells[GridPosition(column: 0, row: 2)])).maxY

        let lowered = actions.drop(battery.id, CGSize(width: 4, height: down - 5))
        let blocked = actions.drop(clock.id, CGSize(width: right * 1.2, height: 0))
        let moved   = actions.drop(clock.id, CGSize(width: right * 10.4, height: 3))

        #expect(lowered && !blocked && moved)
        #expect(host.arrangement == [clock.id: placement(10, 1, tall), battery.id: placement(4, 2, wide)])
    }

    @Test
    func removingSuspendsTheWidgetAndOffersItInTheGallery() {
        let (host, clock, battery) = host()
        var changes           = 0
        host.onContentChanged = { changes += 1 }

        host.remove(battery.id)

        #expect(host.arrangement[battery.id] == nil)
        #expect(battery.suspensions == 1)
        #expect(clock.suspensions == 0)
        #expect(host.gallery.map(\.id) == [battery.id])
        #expect(changes == 1)
    }

    @Test
    func addingPlacesTheChosenSizeAtTheFirstFreeFitAndActivatesIt() {
        let (host, _, battery) = host()
        host.remove(battery.id)

        let added = host.add(battery.id, size: tall, on: grid)

        #expect(added)
        #expect(host.arrangement[battery.id] == placement(4, 1, tall))
        #expect(battery.activations == 2)
        #expect(host.gallery.isEmpty)
    }

    @Test
    func resizingKeepsItsPlaceWhenItFitsAndMovesToTheFirstFreeFitOtherwise() {
        let (host, clock, battery) = host()

        let shrunk = host.resize(clock.id, to: wide, on: grid)
        #expect(shrunk)
        #expect(host.arrangement[clock.id] == placement(0, 1, wide))

        _ = host.move(battery.id, to: GridPosition(column: 0, row: 2), on: grid)
        let grown = host.resize(clock.id, to: tall, on: grid)

        #expect(grown)
        #expect(host.arrangement[clock.id] == placement(4, 1, tall))
    }

    @Test
    func theResizeControlStepsToTheNextSizeThatFits() {
        let host  = WidgetHost()
        let clock = EditableWidgetFixture("clock", sizes: [wide, tall, GridSpan(columns: 14, rows: 2)])
        let other = EditableWidgetFixture("other", sizes: [wide])
        host.register(clock)
        host.register(other)
        host.update(state: .open, display: builtIn)
        _ = host.move(other.id, to: GridPosition(column: 10, row: 0), on: grid)

        #expect(host.resizeToNextSize(clock.id, on: grid))
        #expect(host.arrangement[clock.id]?.span == tall)

        #expect(host.resizeToNextSize(clock.id, on: grid))
        #expect(host.arrangement[clock.id]?.span == GridSpan(columns: 14, rows: 2))

        #expect(host.resizeToNextSize(clock.id, on: grid))
        #expect(host.arrangement[clock.id]?.span == wide)
    }

    @Test
    func aResizeWithNoRoomAnywhereIsRefused() {
        let host  = WidgetHost()
        let clock = EditableWidgetFixture("clock", sizes: [GridSpan(columns: 14, rows: 1), GridSpan(columns: 14, rows: 2)])
        let other = EditableWidgetFixture("other", sizes: [GridSpan(columns: 14, rows: 1)])
        host.register(clock)
        host.register(other)
        host.update(state: .open, display: builtIn)

        let grown = host.resize(clock.id, to: GridSpan(columns: 14, rows: 2), on: grid)

        #expect(!grown)
        #expect(host.arrangement[clock.id] == placement(0, 1, GridSpan(columns: 14, rows: 1)))
    }

    @Test
    func eachDisplayKeepsItsOwnArrangement() {
        let (host, clock, battery) = host()
        host.remove(battery.id)
        host.update(state: .closed)

        host.update(state: .open, display: external)

        #expect(host.arrangement == [clock.id: placement(0, 1, tall), battery.id: placement(4, 1, wide)])
        #expect(battery.isActive)

        host.update(state: .closed)
        host.update(state: .open, display: builtIn)

        #expect(host.arrangement == [clock.id: placement(0, 1, tall)])
        #expect(!battery.isActive)
    }

    @Test
    func anEditedArrangementLeavesANewWidgetInTheGallery() {
        let (host, _, battery) = host()
        _ = host.move(battery.id, to: GridPosition(column: 4, row: 2), on: grid)
        let timer = EditableWidgetFixture("timer", sizes: [wide])

        host.register(timer)

        #expect(host.arrangement[timer.id] == nil)
        #expect(host.gallery.map(\.id) == [timer.id])
    }

    @Test
    func anAbsentWidgetKeepsItsPlaceUnlessAnEditCoversIt() {
        let (host, clock, battery) = host()
        _ = host.move(battery.id, to: GridPosition(column: 4, row: 2), on: grid)
        host.unregister(id: battery.id)
        host.register(battery)

        #expect(host.arrangement[battery.id] == placement(4, 2, wide))

        host.unregister(id: battery.id)
        _ = host.move(clock.id, to: GridPosition(column: 3, row: 1), on: grid)
        host.register(battery)

        #expect(host.arrangement[battery.id] == nil)
        #expect(host.gallery.map(\.id) == [battery.id])
    }

    /// editingLayout is the built-in page's layout with the board's actions bound to it.
    private func editing(_ host: WidgetHost) -> (NotchLayout, WidgetBoardView.Actions) {
        let layout = NotchLayoutResolver().resolve(
            interior     : CGRect(x: 0, y: 0, width: 640, height: 180),
            notchWidth   : 200,
            topBandHeight: 36,
            placements   : host.arrangement
        )

        return (layout, host.actions(for: layout, setEditing: { _ in }))
    }

    @Test
    func aDragHighlightsTheCellsItWouldLandOnAndWhetherTheyFit() throws {
        let (host, clock, battery) = host()
        let (layout, actions)      = editing(host)
        let origin = try #require(layout.cells[GridPosition(column: 0, row: 1)])
        let right  = try #require(layout.cells[GridPosition(column: 1, row: 1)]).minX - origin.minX
        let down   = origin.maxY - (try #require(layout.cells[GridPosition(column: 0, row: 2)])).maxY

        let lowered = try #require(actions.target(battery.id, CGSize(width: 4, height: down - 5)))
        let blocked = try #require(actions.target(clock.id, CGSize(width: right * 1.2, height: 0)))

        #expect(lowered.placement == placement(4, 2, wide))
        #expect(lowered.fits)
        #expect(lowered.cells.count == 4)
        #expect(!blocked.fits)
        #expect(host.arrangement[battery.id] == placement(4, 1, wide))
    }

    @Test
    func aResizeDragPicksTheNearestDeclaredSizeAndKeepsItsCorner() throws {
        let (host, clock, _)  = host()
        let (layout, actions) = editing(host)
        let frame = try #require(layout.frames[clock.id])

        let shorter = try #require(actions.resizeTarget(clock.id, CGSize(width: 0, height: -frame.height * 0.45)))
        let same    = try #require(actions.resizeTarget(clock.id, CGSize(width: 6, height: 4)))

        #expect(shorter.placement == placement(0, 1, wide))
        #expect(shorter.fits)
        #expect(same.placement == placement(0, 1, tall))
        #expect(actions.commitResize(clock.id, wide))
        #expect(host.arrangement[clock.id] == placement(0, 1, wide))
    }

    @Test
    func aStretchStopsAtTheLargestAndSmallestSizesTheWidgetDeclares() throws {
        let (host, clock, _)  = host()
        let (layout, _)       = editing(host)
        let limits = try #require(host.sizeLimits(of: clock.id, in: layout))
        let tallest = try #require(layout.frames[clock.id])

        #expect(limits.maximum == tallest.size)
        #expect(limits.minimum.width == tallest.width)
        #expect(limits.minimum.height < tallest.height)
    }

    @Test
    func aTickMarksEveryNewCellAndNothingElse() {
        let here  = WidgetBoardView.Target(placement: placement(0, 1, wide), cells: [], fits: true)
        let there = WidgetBoardView.Target(placement: placement(1, 1, wide), cells: [], fits: false)

        #expect(WidgetBoardView.ticks(from: nil, to: here))
        #expect(WidgetBoardView.ticks(from: here, to: there))
        #expect(!WidgetBoardView.ticks(from: here, to: here))
        #expect(!WidgetBoardView.ticks(from: here, to: nil))
    }
}
