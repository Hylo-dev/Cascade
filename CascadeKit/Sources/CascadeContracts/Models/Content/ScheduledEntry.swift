//
//  ScheduledEntry.swift
//  CascadeKit
//

import Foundation

/// ScheduledEntry is a validated value in the version 1 addon protocol.
public struct ScheduledEntry: Codable, Equatable, Sendable {

    public let date   : Date
    public let content: PresentationSet

    public init(
        date   : Date,
        content: PresentationSet
    ) throws {
        self.date    = date
        self.content = content

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        date          = try container.decode(Date.self, forKey: .date)
        content       = try container.decode(PresentationSet.self, forKey: .content)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.finite(date)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case date
        case content
    }
}
