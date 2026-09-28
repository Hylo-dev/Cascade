//
//  AddonRequirement.swift
//  CascadeKit
//

import Foundation

/// AddonRequirement is a validated value in the version 1 addon protocol.
public struct AddonRequirement: Codable, Equatable, Sendable {
    public let kind: Kind
    public let id: String?
    public let version: String?
    public let bundleID: AddonID?
    public let state: ApplicationState?
    public let anyOf: [RequirementAlternative]?

    public init(
        kind: Kind,
        id: String?,
        version: String?,
        bundleID: AddonID?,
        state: ApplicationState?,
        anyOf: [RequirementAlternative]?
    ) throws {
        self.kind = kind
        self.id = id
        self.version = version
        self.bundleID = bundleID
        self.state = state
        self.anyOf = anyOf
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.require(decoder.codingPath.count <= 12, "Requirement nesting exceeds limit")
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        bundleID = try container.decodeIfPresent(AddonID.self, forKey: .bundleID)
        state = try container.decodeIfPresent(ApplicationState.self, forKey: .state)
        anyOf = try container.decodeIfPresent([RequirementAlternative].self, forKey: .anyOf)
        try validate()
    }

    public func validate() throws {
        switch kind {
        case .hostCapability, .service:
            try ContractValidation.require(
                id.map(ContractValidation.identifier) == true && version.map(ContractValidation.range) == true
                    && bundleID == nil && state == nil && anyOf == nil,
                "Invalid service requirement"
            )
            if kind == .hostCapability {
                try ContractValidation.require(
                    [
                        "cascade.activities", "cascade.scheduler", "cascade.widgets", "cascade.notices",
                        "cascade.storage",
                    ].contains(id ?? ""),
                    "Unknown mandatory host capability"
                )
            }
        case .application:
            try ContractValidation.require(
                bundleID != nil && state != nil && id == nil && version == nil && anyOf == nil,
                "Invalid application condition"
            )
        case .anyOf:
            try ContractValidation.require(
                id == nil && version == nil && bundleID == nil && state == nil,
                "Invalid fallback fields"
            )
            let alternatives = anyOf ?? []
            try ContractValidation.require(
                !alternatives.isEmpty && alternatives.count <= 8,
                "Fallback requires 1...8 alternatives"
            )
            try ContractValidation.unique(alternatives.map(\.id), "Duplicate alternatives")
            try ContractValidation.require(
                alternatives.allSatisfy { $0.requires.allSatisfy { $0.kind != .anyOf } },
                "Nested fallback is forbidden"
            )
        }
    }
    public enum Kind: String, Codable, Sendable { case hostCapability, service, application, anyOf }
    public enum ApplicationState: String, Codable, Sendable { case installed, running }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case id
        case version
        case bundleID
        case state
        case anyOf
    }
}
