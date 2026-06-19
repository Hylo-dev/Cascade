//
//  WidgetPlacement.swift
//  CascadeKit
//

import Foundation

/// WidgetPlacement is where a widget currently sits on the grid: its origin
/// (`position`) and footprint (`span`). It is the *mutable arrangement* the user
/// edits by drag-and-drop; the resolver turns a set of placements into pixel
/// frames, it does not decide the placements itself.
nonisolated struct WidgetPlacement: Equatable, Sendable {

    let position: GridPosition
    let span    : GridSpan

    init(
        position: GridPosition,
        span    : GridSpan
    ) {
        self.position = position
        self.span     = span
    }
}
