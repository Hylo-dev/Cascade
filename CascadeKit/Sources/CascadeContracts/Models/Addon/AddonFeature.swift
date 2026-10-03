//
//  AddonFeature.swift
//  CascadeKit
//

import Foundation

/// AddonFeature is a validated value in the version 1 addon protocol.
public struct AddonFeature: Codable, Equatable, Sendable {

    public let id                : String
    public let requires          : [AddonRequirement]
    public let actions           : [String]?
    public let supportsFullscreen: Bool

    public init(
        id                : String,
        requires          : [AddonRequirement],
        actions           : [String]?,
        supportsFullscreen: Bool = false
    ) throws {
        self.id                 = id
        self.requires           = requires
        self.actions            = actions
        self.supportsFullscreen = supportsFullscreen

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id                 = try container.decode(String.self, forKey: .id)
        requires           = try container.decode([AddonRequirement].self, forKey: .requires)
        actions            = try container.decodeIfPresent([String].self, forKey: .actions)
        supportsFullscreen = try container.decodeIfPresent(Bool.self, forKey: .supportsFullscreen) ?? false

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            ContractValidation.identifier(id) && requires.count <= 32,
            "Invalid feature"
        )
        try ContractValidation.unique(actions ?? [], "Duplicate actions")
        try ContractValidation.require(
            (actions ?? []).allSatisfy(ContractValidation.identifier),
            "Invalid action ID"
        )
    }

    /// encode preserves the legacy closed manifest shape unless this feature opts in.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(requires, forKey: .requires)
        try container.encodeIfPresent(actions, forKey: .actions)
        if supportsFullscreen { try container.encode(true, forKey: .supportsFullscreen) }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case id
        case requires = "REQUIRES"
        case actions
        case supportsFullscreen
    }
}
