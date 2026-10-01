//
//  PluginWidgetSize.swift
//  CascadeKit
//

import Foundation

/// PluginWidgetSize is a widget's footprint on a page, in slots: "2x1" is two columns by one
/// row. Pages are at most four slots each way.
public struct PluginWidgetSize: Codable, Hashable, Sendable {

    public let columns: Int
    public let rows   : Int

    public init(
        columns: Int,
        rows   : Int
    ) throws {
        self.columns = columns
        self.rows    = rows

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let text  = try decoder.singleValueContainer().decode(String.self)
        let parts = text.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let columns = Int(parts[0]),
              let rows    = Int(parts[1])
        else { throw AddonFailure(code: .invalidPayload, reason: "Invalid widget size") }

        try self.init(columns: columns, rows: rows)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("\(columns)x\(rows)")
    }

    public func validate() throws {
        try ContractValidation.require(
            (1...4).contains(columns) && (1...4).contains(rows),
            "Widget size out of range"
        )
    }
}
