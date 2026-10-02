//
//  PluginComponentReference.swift
//  CascadeKit
//

import Foundation

/// PluginComponentReference names a tier-2 component and the version a feature or a document
/// was written for. The manifest checks it against the catalog; the kernel checks a document's
/// references against what its feature declared.
public struct PluginComponentReference: Codable, Hashable, Sendable {

    public let id     : String
    public let version: Int

    public init(
        id     : String,
        version: Int
    ) throws {
        self.id      = id
        self.version = version

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id            = try container.decode(String.self, forKey: .id)
        version       = try container.decode(Int.self, forKey: .version)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(ContractValidation.identifier(id), "Invalid component ID")
        try ContractValidation.require(version >= 1, "Invalid component version")
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case id
        case version
    }
}
