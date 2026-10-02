//
//  PluginCompatibility.swift
//  CascadeKit
//

import Foundation

/// PluginCompatibility states the oldest macOS a plugin supports, never older than Cascade's
/// own floor of macOS 15, and the plugin protocol it speaks.
public struct PluginCompatibility: Codable, Equatable, Sendable {

    public let macOS          : String
    public let cascadeProtocol: PluginProtocolVersion

    public init(
        macOS          : String,
        cascadeProtocol: PluginProtocolVersion
    ) throws {
        self.macOS           = macOS
        self.cascadeProtocol = cascadeProtocol

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container   = try decoder.container(keyedBy: CodingKeys.self)
        macOS           = try container.decode(String.self, forKey: .macOS)
        cascadeProtocol = try container.decode(PluginProtocolVersion.self, forKey: .cascadeProtocol)

        try validate()
    }

    public func validate() throws {
        let major = Int(macOS.prefix { $0 != "." }) ?? 0

        try ContractValidation.require(
            macOS.utf8.count <= 16
                && macOS.range(of: "^[1-9][0-9]*\\.[0-9]+$", options: .regularExpression) != nil
                && major >= 15,
            "Invalid macOS requirement"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case macOS
        case cascadeProtocol
    }
}
