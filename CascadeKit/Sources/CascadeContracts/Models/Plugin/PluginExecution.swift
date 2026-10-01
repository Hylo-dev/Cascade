//
//  PluginExecution.swift
//  CascadeKit
//

import Foundation

/// PluginExecution keeps only the type the host instantiates. Execution mode and trust are
/// absent on purpose (D4): a manifest that states them is rejected, because the host takes
/// both from the package signature.
public struct PluginExecution: Codable, Equatable, Sendable {

    public let entryPoint: String

    public init(entryPoint: String) throws {
        self.entryPoint = entryPoint

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        entryPoint    = try container.decode(String.self, forKey: .entryPoint)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            entryPoint.utf8.count <= 128
                && entryPoint.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil,
            "Invalid entry point"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case entryPoint
    }
}
