//
//  AddonID.swift
//  CascadeKit
//

import Foundation

/// AddonID names an addon; the host must authenticate its publisher independently.
public struct AddonID: RawRepresentable, Codable, Hashable, Sendable {

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
            throw AddonFailure(code: .invalidPayload, reason: "Invalid addon ID")
        }

        self = identity
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
