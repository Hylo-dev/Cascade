//
//  FileWorkspaceSnapshot.swift
//  Cascade
//

import Foundation

/// FileWorkspaceSnapshot is one bounded page of a shelf, not the full collection.
public struct FileWorkspaceSnapshot: Codable, Equatable, Sendable {
    public let revision  : UInt64
    public let entries   : [FileWorkspaceEntry]
    public let totalCount: Int
    public let nextCursor: String?
    public let jobs      : [FileConversionJobSnapshot]

    public init(
        revision  : UInt64,
        entries   : [FileWorkspaceEntry],
        totalCount: Int,
        nextCursor: String?,
        jobs      : [FileConversionJobSnapshot]
    ) throws {
        self.revision   = revision
        self.entries    = entries
        self.totalCount = totalCount
        self.nextCursor = nextCursor
        self.jobs       = jobs
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown file workspace snapshot field"
        )
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let entries = try BoundedContractArray.decode(
            FileWorkspaceEntry.self,
            from   : values.superDecoder(forKey: .entries),
            maximum: 32
        )
        let jobs = try BoundedContractArray.decode(
            FileConversionJobSnapshot.self,
            from   : values.superDecoder(forKey: .jobs),
            maximum: 32
        )
        try self.init(
            revision  : values.decode(UInt64.self, forKey: .revision),
            entries   : entries,
            totalCount: values.decode(Int.self, forKey: .totalCount),
            nextCursor: values.decodeIfPresent(String.self, forKey: .nextCursor),
            jobs      : jobs
        )
    }

    public func validate() throws {
        try ContractValidation.require(
            entries.count <= 32 && totalCount >= entries.count
                && Set(entries.map(\.id)).count == entries.count,
            "Invalid file workspace entries or total count"
        )
        try ContractValidation.require(
            jobs.count <= 32 && Set(jobs.map(\.id)).count == jobs.count,
            "Invalid file workspace jobs"
        )
        try FileWorkspaceWire.validateCursor(nextCursor)
        for entry in entries { try entry.validate() }
        for job in jobs { try job.validate() }
    }

    /// encode enforces the same wire limit that decode applies before parsing.
    public func encode() throws -> Data {
        try validate()
        let data = try JSONEncoder().encode(self)
        try ContractValidation.require(data.count <= 65_536, "File workspace snapshot exceeds 64 KiB")
        return data
    }

    /// decode rejects oversized raw messages before Foundation parses JSON.
    public static func decode(_ data: Data) throws -> Self {
        try ContractValidation.require(data.count <= 65_536, "File workspace snapshot exceeds 64 KiB")
        return try JSONDecoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case revision, entries, totalCount, nextCursor, jobs
    }
}
