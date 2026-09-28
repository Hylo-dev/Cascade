//
//  FileWorkspaceCommand.swift
//  CascadeKit
//

import Foundation

/// FileWorkspaceCommand expresses shelf operations using only bounded identifiers.
public enum FileWorkspaceCommand: Codable, Equatable, Sendable {
    case list(cursor: String?)
    case remove(ids: [UUID], revision: UInt64)
    case relink(id: UUID)
    case convert(ids: [UUID], formatID: String, revision: UInt64)
    case cancel(jobID: UUID)

    /// validate checks locally constructed cases before they enter the broker.
    public func validate() throws {
        switch self {
        case .list(let cursor):
            try FileWorkspaceWire.validateCursor(cursor)
        case .remove(let ids, _):
            try FileWorkspaceWire.validateIDs(ids, requiresNonempty: true)
        case .convert(let ids, let formatID, _):
            try FileWorkspaceWire.validateIDs(ids, requiresNonempty: true)
            try ContractValidation.require(ContractValidation.identifier(formatID), "Invalid conversion format ID")
        case .relink, .cancel:
            break
        }
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try values.decode(Kind.self, forKey: .kind)
        let fields = try decoder.container(keyedBy: WireKey.self)
        let allowed: Set<String>
        switch kind {
        case .list: allowed = ["kind", "cursor"]
        case .remove: allowed = ["kind", "ids", "revision"]
        case .relink: allowed = ["kind", "id"]
        case .convert: allowed = ["kind", "ids", "formatID", "revision"]
        case .cancel: allowed = ["kind", "jobID"]
        }
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: allowed),
            "Invalid file workspace command fields"
        )
        switch kind {
        case .list:
            self = .list(cursor: try values.decodeIfPresent(String.self, forKey: .cursor))
        case .remove:
            self = .remove(
                ids     : try Self.decodeIDs(values),
                revision: try values.decode(UInt64.self, forKey: .revision)
            )
        case .relink:
            self = .relink(id: try values.decode(UUID.self, forKey: .id))
        case .convert:
            self = .convert(
                ids     : try Self.decodeIDs(values),
                formatID: try values.decode(String.self, forKey: .formatID),
                revision: try values.decode(UInt64.self, forKey: .revision)
            )
        case .cancel:
            self = .cancel(jobID: try values.decode(UUID.self, forKey: .jobID))
        }
        try validate()
    }

    public func encode(to encoder: any Encoder) throws {
        try validate()
        var values = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .list(let cursor):
            try values.encode(Kind.list, forKey: .kind)
            try values.encodeIfPresent(cursor, forKey: .cursor)
        case .remove(let ids, let revision):
            try values.encode(Kind.remove, forKey: .kind)
            try values.encode(ids, forKey: .ids)
            try values.encode(revision, forKey: .revision)
        case .relink(let id):
            try values.encode(Kind.relink, forKey: .kind)
            try values.encode(id, forKey: .id)
        case .convert(let ids, let formatID, let revision):
            try values.encode(Kind.convert, forKey: .kind)
            try values.encode(ids, forKey: .ids)
            try values.encode(formatID, forKey: .formatID)
            try values.encode(revision, forKey: .revision)
        case .cancel(let jobID):
            try values.encode(Kind.cancel, forKey: .kind)
            try values.encode(jobID, forKey: .jobID)
        }
    }

    private static func decodeIDs(_ values: KeyedDecodingContainer<CodingKeys>) throws -> [UUID] {
        try BoundedContractArray.decode(
            UUID.self,
            from   : values.superDecoder(forKey: .ids),
            maximum: 32
        )
    }

    private enum Kind: String, Codable { case list, remove, relink, convert, cancel }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case kind, cursor, ids, revision, id, formatID, jobID
    }
}
