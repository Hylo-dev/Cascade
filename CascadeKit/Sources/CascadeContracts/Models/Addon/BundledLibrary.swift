//
//  BundledLibrary.swift
//  CascadeKit
//

import Foundation

/// BundledLibrary is a validated value in the version 1 addon protocol.
public struct BundledLibrary: Codable, Equatable, Sendable {
    public let name: String
    public let version: String

    public init(
        name: String,
        version: String
    ) throws {
        self.name = name
        self.version = version
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        version = try container.decode(String.self, forKey: .version)
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            ContractValidation.identifier(name) && ContractValidation.semver(version),
            "Invalid bundled library"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case name
        case version
    }
}
