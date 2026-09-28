//
//  FileWorkspaceEntry.swift
//  Cascade
//

import Foundation

/// FileAvailability describes whether a shelf entry can currently be used.
public enum FileAvailability: String, Codable, Equatable, Sendable {
    case available, unavailable, receiving
}

/// FileOwnership distinguishes an external reference from a managed copy.
public enum FileOwnership: String, Codable, Equatable, Sendable {
    case externalReference, managed
}

/// FileWorkspaceEntry is display metadata; its UUID never grants file access.
public struct FileWorkspaceEntry: Codable, Equatable, Sendable {
    public let id              : UUID
    public let name            : String
    public let typeIdentifier  : String
    public let availability    : FileAvailability
    public let ownership       : FileOwnership
    public let thumbnailAssetID: String?

    public init(
        id              : UUID,
        name            : String,
        typeIdentifier  : String,
        availability    : FileAvailability,
        ownership       : FileOwnership,
        thumbnailAssetID: String?
    ) throws {
        self.id               = id
        self.name             = name
        self.typeIdentifier   = typeIdentifier
        self.availability     = availability
        self.ownership        = ownership
        self.thumbnailAssetID = thumbnailAssetID
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown file entry field"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            id              : values.decode(UUID.self, forKey: .id),
            name            : values.decode(String.self, forKey: .name),
            typeIdentifier  : values.decode(String.self, forKey: .typeIdentifier),
            availability    : values.decode(FileAvailability.self, forKey: .availability),
            ownership       : values.decode(FileOwnership.self, forKey: .ownership),
            thumbnailAssetID: values.decodeIfPresent(String.self, forKey: .thumbnailAssetID)
        )
    }

    /// validate bounds untrusted labels and keeps asset aliases free of paths or URLs.
    public func validate() throws {
        try ContractValidation.require(
            !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.utf8.count <= 4_096,
            "Invalid file name"
        )
        try FileWorkspaceWire.validateTypeIdentifier(typeIdentifier)
        try ContractValidation.require(
            thumbnailAssetID.map(ContractValidation.identifier) ?? true,
            "Invalid thumbnail asset ID"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case id, name, typeIdentifier, availability, ownership, thumbnailAssetID
    }
}

/// FileWorkspaceWire contains only validation shared by the small file workspace values.
enum FileWorkspaceWire {
    static func validateTypeIdentifier(_ value: String) throws {
        try ContractValidation.require(
            !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && value.utf8.count <= 128
                && value.utf8.allSatisfy { $0 < 128 },
            "Invalid file type identifier"
        )
    }

    static func validateCursor(_ value: String?) throws {
        try ContractValidation.require(
            value.map { !$0.isEmpty && $0.utf8.count <= 128 } ?? true,
            "Invalid file workspace cursor"
        )
    }

    static func validateIDs(_ values: [UUID], requiresNonempty: Bool) throws {
        try ContractValidation.require(
            values.count <= 32 && (!requiresNonempty || !values.isEmpty)
                && Set(values).count == values.count,
            "Invalid file workspace IDs"
        )
    }
}
