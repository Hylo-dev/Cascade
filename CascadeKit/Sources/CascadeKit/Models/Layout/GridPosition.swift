//
//  GridPosition.swift
//  CascadeKit
//

import Foundation

/// GridPosition is the origin cell of a widget block on the unified notch grid:
/// `column` from the leading edge, `row` from the top (0 = the notch band row,
/// 1 and 2 = the two main rows below the physical notch).
nonisolated struct GridPosition: Equatable, Hashable, Sendable {

    let column: Int
    let row   : Int

    init(
        column: Int,
        row   : Int
    ) {
        self.column = column
        self.row    = row
    }
}
