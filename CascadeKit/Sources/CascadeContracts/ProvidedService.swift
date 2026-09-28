//
//  ProvidedService.swift
//  CascadeKit
//

import Foundation

/// ProvidedService is a validated value in the version 1 addon protocol.
public struct ProvidedService: Codable, Equatable, Sendable {
    public let kind: Kind
    public let id: String
    public let version: String

    public init(
        kind: Kind,
        id: String,
        version: String
    ) throws {
        self.kind = kind
        self.id = id
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
        kind = try container.decode(Kind.self, forKey: .kind)
        id = try container.decode(String.self, forKey: .id)
        version = try container.decode(String.self, forKey: .version)
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            ContractValidation.identifier(id) && ContractValidation.semver(version),
            "Invalid provided service"
        )
    }
    public enum Kind: String, Codable, Sendable { case service }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind
        case id
        case version
    }
}
