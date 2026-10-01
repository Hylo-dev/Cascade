//
//  RequirementAlternative.swift
//  CascadeKit
//

import Foundation

/// RequirementAlternative is a validated value in the version 1 addon protocol.
public struct RequirementAlternative: Codable, Equatable, Sendable {

    public let id      : String
    public let requires: [AddonRequirement]

    public init(
        id      : String,
        requires: [AddonRequirement]
    ) throws {
        self.id       = id
        self.requires = requires

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.require(
            decoder.codingPath.count <= 12,
            "Requirement nesting exceeds limit"
        )

        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id            = try container.decode(String.self, forKey: .id)
        requires      = try container.decode([AddonRequirement].self, forKey: .requires)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            ContractValidation.identifier(id) && !requires.isEmpty && requires.count <= 32,
            "Invalid fallback alternative"
        )
        try ContractValidation.require(
            requires.allSatisfy { $0.kind != .anyOf },
            "Nested fallback is forbidden"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case id
        case requires = "REQUIRES"
    }
}
