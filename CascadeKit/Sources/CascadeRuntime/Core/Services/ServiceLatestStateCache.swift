//
//  ServiceLatestStateCache.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// ServiceLatestStateCache is an actor-confined compact cache. Replacement is prepaid before
/// copying; readers may borrow bytes only in a synchronous no-suspension encode/handoff scope.
struct ServiceLatestStateCache: Sendable {

    struct Entry: Sendable {

        let sourceID: UUID
        let key     : ServiceRegistry.SourceKey
        let revision: UInt64
        let response: ServiceResponse

        var bytes: Int { Self.metadataBytes + response.payload.count }

        static let metadataBytes = max(2_048, MemoryLayout<Self>.stride * 4)
    }

    static let maximumEntries = 128

    var entries: [UUID: Entry] = [:]

    func retainedBytes(owner: AddonID) -> Int {
        entries.values.filter { $0.key.provider.addonID == owner }.reduce(0) { $0 + $1.bytes }
    }

    func nextRevision(sourceID: UUID) throws -> UInt64 {
        let previous = entries[sourceID]?.revision ?? 0

        guard previous < UInt64.max,
              entries[sourceID] != nil || entries.count < Self.maximumEntries
        else {
            throw ServiceBroker.failure(.resourceDenied)
        }

        return previous + 1
    }

    mutating func replace(
        sourceID: UUID,
        key     : ServiceRegistry.SourceKey,
        response: ServiceResponse,
        revision: UInt64
    ) throws {
        guard revision == (try nextRevision(sourceID: sourceID)),
              response.payload.count <= 65_536,
              response.contractID == key.serviceID,
              response.operation == key.operation
        else {
            throw ServiceBroker.failure(.invalidPayload)
        }

        let compact = try ServiceResponse(
            schemaVersion: response.schemaVersion,
            contractID   : response.contractID,
            operation    : response.operation,
            payload      : response.payload.withUnsafeBytes { Data($0) }
        )
        entries[sourceID] = Entry(
            sourceID: sourceID,
            key     : key,
            revision: revision,
            response: compact
        )
    }
}
