//
//  AddonFeature.swift
//  CascadeKit
//

import Foundation

/// AddonFeature is a validated value in the version 1 addon protocol.
public struct AddonFeature: Codable, Equatable, Sendable {
    public let id: String
    public let requires: [AddonRequirement]
    public let actions: [String]?

    public init(
        id: String,
        requires: [AddonRequirement],
        actions: [String]?
    ) throws {
        self.id = id
        self.requires = requires
        self.actions = actions
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        requires = try container.decode([AddonRequirement].self, forKey: .requires)
        actions = try container.decodeIfPresent([String].self, forKey: .actions)
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(ContractValidation.identifier(id) && requires.count <= 32, "Invalid feature")
        try ContractValidation.unique(actions ?? [], "Duplicate actions")
        try ContractValidation.require((actions ?? []).allSatisfy(ContractValidation.identifier), "Invalid action ID")
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case requires = "REQUIRES"
        case actions
    }
}
