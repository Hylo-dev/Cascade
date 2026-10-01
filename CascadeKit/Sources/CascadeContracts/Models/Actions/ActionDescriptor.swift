//
//  ActionDescriptor.swift
//  CascadeKit
//

import Foundation

/// ActionDescriptor carries an action identity and bounded input, never executable code.
public struct ActionDescriptor: Codable, Equatable, Sendable {

    public let schemaVersion: Int
    public let id           : String
    public let label        : String
    public let payload      : Data

    public init(
        id     : String,
        label  : String,
        payload: Data = Data()
    ) throws {
        schemaVersion = 1
        self.id       = id
        self.label    = label
        self.payload  = payload

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: ["schemaVersion", "id", "label", "payload"]),
            "Unknown action field"
        )

        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        id            = try container.decode(String.self, forKey: .id)
        label         = try container.decode(String.self, forKey: .label)
        payload       = try container.decode(Data.self, forKey: .payload)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            schemaVersion == 1 && ContractValidation.identifier(id),
            "Invalid action descriptor"
        )
        try ContractValidation.require(
            !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && label.utf8.count <= 4096,
            "Action requires accessible label"
        )
        try ContractValidation.require(payload.count <= 4096, "Action payload exceeds 4 KiB")
    }

    private enum CodingKeys: String, CodingKey {

        case schemaVersion, id, label, payload
    }
}
