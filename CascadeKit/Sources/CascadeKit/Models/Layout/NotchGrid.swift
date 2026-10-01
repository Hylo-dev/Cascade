//
//  NotchGrid.swift
//  CascadeKit
//

/// NotchGrid is the grid's topology without its pixels: how many columns there are and which
/// columns of the notch band (row 0) survive beside the physical notch. It is also where the
/// editing rules live, so a drop, a resize, an addition and the auto-placement of a new widget
/// all agree on what fits.
///
/// The rules are deliberately few. A placement fits when every cell it covers exists and no
/// other widget covers it. The band is the notch's own height, so only a one-row widget may sit
/// in it. The first free fit scans the two main rows from the leading edge, never the band:
/// the band depends on the live notch geometry, so a widget only goes there by hand.
nonisolated struct NotchGrid: Equatable, Sendable {

    let columns    : Int
    let bandColumns: Range<Int>

    /// isAvailable tells whether a cell exists: every cell of the two main rows, and in the band
    /// only the trailing cells beside the notch.
    func isAvailable(_ cell: GridPosition) -> Bool {
        guard cell.column >= 0, cell.column < columns else { return false }

        return cell.row == 0 ? bandColumns.contains(cell.column) : (1 ... 2).contains(cell.row)
    }

    /// fits tells whether `placement` could stand on the grid next to `others`.
    func fits(
        _ placement: WidgetPlacement,
        among others: some Sequence<WidgetPlacement>
    ) -> Bool {
        let position = placement.position
        let span     = placement.span
        guard position.row != 0 || span.rows == 1 else { return false }

        for column in position.column ..< position.column + span.columns {
            for row in position.row ..< position.row + span.rows
                where !isAvailable(GridPosition(column: column, row: row)) {
                return false
            }
        }

        return !others.contains { $0.overlaps(placement) }
    }

    /// firstFit is the first free block of `span` in the main rows, scanning each row from the
    /// leading edge. A two-row widget can only start on the first main row.
    func firstFit(
        for span    : GridSpan,
        among others: [WidgetPlacement]
    ) -> WidgetPlacement? {
        let originRows = span.rows == 2 ? [1] : [1, 2]

        for row in originRows {
            for column in 0 ... max(0, columns - span.columns) {
                let candidate = WidgetPlacement(
                    position: GridPosition(column: column, row: row),
                    span    : span
                )
                if fits(candidate, among: others) { return candidate }
            }
        }

        return nil
    }
}
