//
//  ProtocolOffer.swift
//  CascadeKit
//

import Foundation

/// ProtocolOffer describes capabilities, never identity or permission. Future
/// versions may be offered alongside common versions without becoming supported.
public struct ProtocolOffer: Codable, Equatable, Sendable {

    public let schemaVersion : Int
    public let major         : Int
    public let minimumMinor  : Int
    public let maximumMinor  : Int
    public let contentSchemas: [Int]

    public init(
        schemaVersion : Int = 1,
        major         : Int,
        minimumMinor  : Int,
        maximumMinor  : Int,
        contentSchemas: [Int]
    ) throws {
        self.schemaVersion  = schemaVersion
        self.major          = major
        self.minimumMinor   = minimumMinor
        self.maximumMinor   = maximumMinor
        self.contentSchemas = contentSchemas

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)) == Set(CodingKeys.allCases.map(\.rawValue)),
            "Protocol offer requires exactly its defined fields"
        )

        let container  = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion  = try container.decode(Int.self, forKey: .schemaVersion)
        major          = try container.decode(Int.self, forKey: .major)
        minimumMinor   = try container.decode(Int.self, forKey: .minimumMinor)
        maximumMinor   = try container.decode(Int.self, forKey: .maximumMinor)
        contentSchemas = try container.decode([Int].self, forKey: .contentSchemas)

        try validate()
    }

    /// validate enforces the same closed offer bounds at construction and decoding.
    public func validate() throws {
        try ContractValidation.require(schemaVersion == 1, "Unsupported protocol offer schema")
        try ContractValidation.require(
            (1...65_535).contains(major)
                && (0...65_535).contains(minimumMinor)
                && (0...65_535).contains(maximumMinor)
                && minimumMinor <= maximumMinor,
            "Invalid protocol version interval"
        )
        try ContractValidation.require(
            (1...8).contains(contentSchemas.count)
                && Set(contentSchemas).count == contentSchemas.count
                && contentSchemas.allSatisfy { (1...65_535).contains($0) },
            "Protocol offer requires 1...8 distinct content schema identifiers"
        )
    }

    /// decode checks the raw byte bound before allocating a decoded JSON object.
    public static func decode(_ data: Data) throws -> Self {
        try ContractValidation.require(data.count <= 8_192, "Protocol offer exceeds 8 KiB")

        return try JSONDecoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case schemaVersion, major, minimumMinor, maximumMinor, contentSchemas
    }
}
