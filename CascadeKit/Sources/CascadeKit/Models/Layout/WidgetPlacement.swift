//
//  WidgetPlacement.swift
//  CascadeKit
//

/// WidgetPlacement is where a widget currently sits on the grid: its origin
/// (`position`) and footprint (`span`). It is the *mutable arrangement* the user
/// edits by drag-and-drop; the resolver turns a set of placements into pixel
/// frames, it does not decide the placements itself.
nonisolated struct WidgetPlacement: Codable, Equatable, Sendable {

    let position: GridPosition
    let span    : GridSpan

    init(
        position: GridPosition,
        span    : GridSpan
    ) {
        self.position = position
        self.span     = span
    }

    /// overlaps tells whether the two blocks share at least one cell.
    func overlaps(_ other: WidgetPlacement) -> Bool {
        position.column < other.position.column + other.span.columns
            && other.position.column < position.column + span.columns
            && position.row < other.position.row + other.span.rows
            && other.position.row < position.row + span.rows
    }
}
