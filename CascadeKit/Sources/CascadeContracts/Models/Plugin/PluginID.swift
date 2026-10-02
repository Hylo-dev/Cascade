//
//  PluginID.swift
//  CascadeKit
//

import Foundation

/// PluginID names a plugin in reverse-DNS form. It says nothing about who published the
/// plugin: the host decides trust and execution mode from the package signature, never from
/// this name. It mirrors `AddonID`, which goes away with the v1 contracts.
public struct PluginID: RawRepresentable, Codable, Hashable, Sendable {

    public let rawValue: String

    public init?(rawValue: String) {
        guard rawValue.utf8.count <= 255,
              rawValue.range(of: "^[a-zA-Z][a-zA-Z0-9-]*(\\.[a-zA-Z][a-zA-Z0-9-]*)+$", options: .regularExpression) != nil
        else { return nil }

        self.rawValue = rawValue
    }

    public init(from decoder: any Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let identity = Self(rawValue: value) else {
            throw AddonFailure(code: .invalidPayload, reason: "Invalid plugin ID")
        }

        self = identity
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
