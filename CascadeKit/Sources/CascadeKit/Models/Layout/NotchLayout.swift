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
/// side (degrading from the configured maximum on a narrow notch).
nonisolated struct NotchLayout: Equatable, Sendable {

    let frames           : [WidgetIdentifier: CGRect]
    let notchColumns     : Int
    let trailingCellCount: Int

    init(
        frames           : [WidgetIdentifier: CGRect],
        notchColumns     : Int,
        trailingCellCount: Int
    ) {
        self.frames            = frames
        self.notchColumns      = notchColumns
        self.trailingCellCount = trailingCellCount
    }
}
