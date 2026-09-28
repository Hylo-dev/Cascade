//
//  AddonCompatibility.swift
//  CascadeKit
//

import Foundation

/// AddonCompatibility is a validated value in the version 1 addon protocol.
public struct AddonCompatibility: Codable, Equatable, Sendable {
    public let macOS: String
    public let cascadeProtocol: ProtocolVersion

    public init(
        macOS: String,
        cascadeProtocol: ProtocolVersion
    ) throws {
        self.macOS = macOS
        self.cascadeProtocol = cascadeProtocol
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        macOS = try container.decode(String.self, forKey: .macOS)
        cascadeProtocol = try container.decode(ProtocolVersion.self, forKey: .cascadeProtocol)
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            macOS.utf8.count <= 64 && macOS.range(of: "^>=([1-9][0-9]*)\\.[0-9]+$", options: .regularExpression) != nil,
            "Invalid macOS requirement"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case macOS
        case cascadeProtocol
    }
}
