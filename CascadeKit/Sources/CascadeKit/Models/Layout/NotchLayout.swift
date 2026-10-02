//
//  NotchLayout.swift
//  CascadeKit
//

import CoreGraphics

/// NotchLayout is the resolved output of `NotchLayoutResolver`: the pixel frame
/// of every placed widget, plus a couple of resolved grid facts useful for the
/// renderer and for tests.
///
/// `notchColumns` and `trailingCellCount` are the "does it actually fit" answer
/// the geometry forces us to compute — how many columns the physical notch eats
/// out of the top band, and how many cells are therefore left on its trailing
/// side (degrading from the configured maximum on a narrow notch). `grid` is the
/// same answer as a topology the editing rules read, and `cells` the frame of
/// every cell that exists, which editing draws and snaps a dragged widget to.
nonisolated struct NotchLayout: Equatable, Sendable {

    let frames           : [WidgetIdentifier: CGRect]
    let cells            : [GridPosition: CGRect]
    let grid             : NotchGrid
    let notchColumns     : Int
    let trailingCellCount: Int

    init(
        frames           : [WidgetIdentifier: CGRect],
        cells            : [GridPosition: CGRect],
        grid             : NotchGrid,
        notchColumns     : Int,
        trailingCellCount: Int
    ) {
        self.frames            = frames
        self.cells             = cells
        self.grid              = grid
        self.notchColumns      = notchColumns
        self.trailingCellCount = trailingCellCount
    }

    /// cell(nearestTopLeading:) is the cell whose top-leading corner is closest to `point`, in
    /// the same y-up coordinates as the frames. Comparing corners rather than centres keeps a
    /// tall widget's snap honest across rows of different heights.
    func cell(nearestTopLeading point: CGPoint) -> GridPosition? {
        cells.min { first, second in
            hypot(first.value.minX - point.x, first.value.maxY - point.y)
                < hypot(second.value.minX - point.x, second.value.maxY - point.y)
        }?.key
    }
}
