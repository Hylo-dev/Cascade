//
//  GridSpan.swift
//  CascadeKit
//

/// GridSpan is a widget's footprint on the notch grid, in cells.
///
/// The grid is two rows tall, so `rows` is clamped to `1...2`; `columns` is free
/// (`1×1` small, `1×n` compact/medium, `2×n` large), iPhone-home-screen style.
/// A widget keeps a normal span and, optionally, an expanded one (Control-Center
/// style) — the resolver only ever maps the *current* span to pixels; deciding
/// when to expand belongs to the interaction layer.
public nonisolated struct GridSpan: Codable, Hashable, Sendable {

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

    /// init(from:) goes through the clamping initializer, so a saved arrangement that was
    /// damaged or written by a future version can never carry an empty or oversized span.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.init(
            columns: try container.decode(Int.self, forKey: .columns),
            rows   : try container.decode(Int.self, forKey: .rows)
        )
    }

    private enum CodingKeys: String, CodingKey {

        case columns
        case rows
    }
}
