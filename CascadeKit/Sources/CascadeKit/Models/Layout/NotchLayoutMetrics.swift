//
//  NotchLayoutMetrics.swift
//  CascadeKit
//

import CoreGraphics

/// NotchLayoutMetrics is the tunable part of the grid: how many columns, the
/// gap between cells, and how many cells the top band may offer beside the
/// notch. The grid *topology* (two main rows, the notch band on top) is rigid;
/// only these spacings are configurable.
nonisolated struct NotchLayoutMetrics: Sendable {

    /// Columns across the full interior width.
    let columns: Int

    /// Gap between adjacent cells, horizontally and vertically.
    let cellGutter: CGFloat

    /// Most cells the top band offers to the trailing side of the notch. The
    /// resolver uses fewer when the gap beside the notch can't hold this many.
    /// The default offers none: a widget squeezed beside the physical notch read
    /// as clutter, so the band stays empty and widgets live in the two main rows.
    let maxTrailingCells: Int

    static let `default` = NotchLayoutMetrics(
        columns         : 14,
        cellGutter      : 6,
        maxTrailingCells: 0
    )
}
