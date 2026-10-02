//
//  PluginProtocolVersion.swift
//  CascadeKit
//

import Foundation

/// PluginProtocolVersion is the plugin protocol a manifest speaks: major 2, from a minimum
/// minor up. The v1 `ProtocolVersion` accepts only major 1, so v2 has its own value.
public struct PluginProtocolVersion: Codable, Equatable, Sendable {

    public let major       : Int
    public let minimumMinor: Int

    public init(
        major       : Int,
        minimumMinor: Int
    ) throws {
        self.major        = major
        self.minimumMinor = minimumMinor

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        major         = try container.decode(Int.self, forKey: .major)
        minimumMinor  = try container.decode(Int.self, forKey: .minimumMinor)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            major == 2 && (0...65_535).contains(minimumMinor),
            "Unsupported plugin protocol"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case major
        case minimumMinor
    }
}
