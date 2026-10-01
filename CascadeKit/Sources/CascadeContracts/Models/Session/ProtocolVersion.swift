//
//  ProtocolVersion.swift
//  CascadeKit
//

import Foundation

/// ProtocolVersion is a validated value in the version 1 addon protocol.
public struct ProtocolVersion: Codable, Equatable, Sendable {

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
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        major         = try container.decode(Int.self, forKey: .major)
        minimumMinor  = try container.decode(Int.self, forKey: .minimumMinor)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            major == 1 && minimumMinor >= 0 && minimumMinor <= 65_535,
            "Unsupported wire protocol"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case major
        case minimumMinor
    }
}
