//
//  NotchLayoutResolver.swift
//  CascadeKit
//

import CoreGraphics

/// NotchLayoutResolver turns a widget arrangement into pixel frames on the
/// unified notch grid. It is pure value math — no AppKit, no state beyond the
/// metrics — so it unit-tests without a screen and never touches the 120 Hz
/// path (the host calls it once per arrangement change, for the open geometry).
///
/// The grid is `columns × 3`: row 0 is the band beside the physical notch
/// (the leading slider, the blocked notch itself, and up to a few trailing
/// cells), rows 1–2 are the two main rows below the notch. Column width is
/// derived to fill the interior; row 0 is the notch's own (shorter) height while
/// rows 1–2 split the rest. The resolver also computes *how much* of the band
/// the notch eats and how many trailing cells survive — the "does it fit" answer
/// the geometry forces.
nonisolated struct NotchLayoutResolver {

    let metrics: NotchLayoutMetrics

    init(metrics: NotchLayoutMetrics = .default) {
        self.metrics = metrics
    }

    /// resolve turns `placements` into frames inside `interior` (the open
    /// notch's safe content area, host coordinates, y growing upward).
    /// `notchWidth` / `topBandHeight` are the physical notch's width and height
    /// (0 width when there is no hardware notch). A placement whose cells aren't
    /// all available is dropped from the result.
    func resolve(
        interior     : CGRect,
        notchWidth   : CGFloat,
        topBandHeight: CGFloat,
        placements   : [WidgetIdentifier: WidgetPlacement]
    ) -> NotchLayout {
        let columns = max(1, metrics.columns)
        let gutter  = metrics.cellGutter

        let cellWidth     = (interior.width - gutter * CGFloat(columns - 1)) / CGFloat(columns)
        let mainRowHeight = (interior.height - topBandHeight - gutter * 2) / 2

        // The physical notch eats columns from the centre of the band; what's
        // left on its trailing side becomes the top-band cells (≤ the max).
        let notchColumns  = notchWidth > 0
            ? min(columns, Int((notchWidth / (cellWidth + gutter)).rounded(.up)))
            : 0
        let notchStart    = (columns - notchColumns) / 2
        let trailingStart = notchStart + notchColumns
        let trailingCells = max(0, min(metrics.maxTrailingCells, columns - trailingStart))

        // y grows upward, so row 0 sits at the top of the interior.
        func rowOriginY(_ row: Int) -> CGFloat {
            switch row {
                case 0:  return interior.maxY - topBandHeight
                case 1:  return interior.maxY - topBandHeight - gutter - mainRowHeight
                default: return interior.maxY - topBandHeight - gutter * 2 - mainRowHeight * 2
            }
        }

        func rowHeight(_ row: Int) -> CGFloat {
            row == 0 ? topBandHeight : mainRowHeight
        }

        func cellOriginX(_ column: Int) -> CGFloat {
            interior.minX + CGFloat(column) * (cellWidth + gutter)
        }

        // Row 0 only offers the trailing cells; rows 1–2 are fully available.
        let grid = NotchGrid(
            columns    : columns,
            bandColumns: trailingStart ..< trailingStart + trailingCells
        )

        var cells: [GridPosition: CGRect] = [:]

        for row in 0 ... 2 {
            for column in 0 ..< columns {
                let cell = GridPosition(column: column, row: row)
                guard grid.isAvailable(cell) else { continue }

                cells[cell] = CGRect(
                    x     : cellOriginX(column),
                    y     : rowOriginY(row),
                    width : cellWidth,
                    height: rowHeight(row)
                )
            }
        }

        // A placement spans from its first cell to its last; if any covered cell
        // is missing, the placement is dropped.
        var frames: [WidgetIdentifier: CGRect] = [:]

        for (id, placement) in placements {
            let firstColumn = placement.position.column
            let firstRow    = placement.position.row
            let lastColumn  = firstColumn + placement.span.columns - 1
            let lastRow     = firstRow + placement.span.rows - 1

            let covered = (firstColumn ... lastColumn).allSatisfy { column in
                (firstRow ... lastRow).allSatisfy { row in
                    cells[GridPosition(column: column, row: row)] != nil
                }
            }

            guard covered,
                  let first = cells[GridPosition(column: firstColumn, row: firstRow)],
                  let last  = cells[GridPosition(column: lastColumn, row: lastRow)]
            else { continue }

            frames[id] = first.union(last)
        }

        return NotchLayout(
            frames           : frames,
            cells            : cells,
            grid             : grid,
            notchColumns     : notchColumns,
            trailingCellCount: trailingCells
        )
    }
}
