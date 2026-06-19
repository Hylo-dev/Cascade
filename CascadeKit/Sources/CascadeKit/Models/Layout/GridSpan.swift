//
//  GridSpan.swift
//  CascadeKit
//

import Foundation

/// GridSpan is a widget's footprint on the notch grid, in cells.
///
/// The grid is two rows tall, so `rows` is clamped to `1...2`; `columns` is free
/// (`1×1` small, `1×n` compact/medium, `2×n` large), iPhone-home-screen style.
/// A widget keeps a normal span and, optionally, an expanded one (Control-Center
/// style) — the resolver only ever maps the *current* span to pixels; deciding
/// when to expand belongs to the interaction layer.
public nonisolated struct GridSpan: Equatable, Sendable {

    public let columns: Int
    public let rows   : Int

    public init(
        columns: Int,
        rows   : Int
    ) {
        self.columns = max(1, columns)
        self.rows    = min(max(1, rows), 2)
    }

    public static let small = GridSpan(columns: 1, rows: 1)
}
