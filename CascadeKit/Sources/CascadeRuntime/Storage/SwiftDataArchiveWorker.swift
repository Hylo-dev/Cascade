//
//  SwiftDataArchiveWorker.swift
//  Cascade
//

import CascadeContracts
import CryptoKit
import Foundation
import SwiftData

/// SwiftDataArchiveRow stores one coherent generation with ordinary in-database Data.
/// No external-storage attribute, relationship or separately committed blob is used.
@Model
final class SwiftDataArchiveRow {
    @Attribute(.unique)
    var namespace     : String
    var publisher     : String
    var addonID       : String
    var formatVersion : Int
    var schemaVersion : Int
    var revision      : String
    var verifiedDigest: String
    var payload       : Data
    var checksum      : Data

    init(
        identity  : VerifiedAddonIdentity,
        generation: SwiftDataArchiveGeneration
    ) {
        namespace      = SwiftDataArchiveWorker.namespace(identity)
        publisher      = identity.publisher
        addonID        = identity.addonID.rawValue
        formatVersion  = 1
        schemaVersion  = generation.schemaVersion
        revision       = String(generation.revision)
        verifiedDigest = generation.verifiedDigest
        payload        = generation.payload
        checksum       = SwiftDataArchiveWorker.checksum(
            identity  : identity,
            generation: generation
        )
    }
}

/// SwiftDataArchiveWorker keeps framework objects on its serial executor.
/// The executor context remains empty. A fresh operation context owns each fetched row,
/// preventing application payload retention between calls; framework caches remain observed.
actor SwiftDataArchiveWorker: ModelActor {
    nonisolated let modelContainer: ModelContainer
    nonisolated let modelExecutor : any ModelExecutor

    init(root: URL) throws {
        guard !Thread.isMainThread else { throw SwiftDataArchiveFailure.unavailable }
        let schema        = Schema([SwiftDataArchiveRow.self])
        let configuration = ModelConfiguration(
            "CascadeOwnerArchive",
            schema          : schema,
            url             : root.appendingPathComponent("archive.store"),
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for           : schema,
            configurations: [configuration]
        )
        let executorContext             = ModelContext(container)
        executorContext.autosaveEnabled = false
        executorContext.undoManager     = nil
        modelContainer                  = container
        modelExecutor                   = DefaultSerialModelExecutor(modelContext: executorContext)
    }

    /// validateArchive checks persisted identity and format without retaining a returned payload.
    func validateArchive(identity: VerifiedAddonIdentity) throws {
        _ = try read(identity: identity)
    }

    /// read returns bounded immutable data only into the host's protected callback scope.
    func read(identity: VerifiedAddonIdentity) throws -> SwiftDataArchiveGeneration? {
        guard !Thread.isMainThread else { throw SwiftDataArchiveFailure.unavailable }
        return try autoreleasepool {
            let context = operationContext()
            guard let row = try row(in: context) else { return nil }
            return try validate(
                row,
                identity: identity
            )
        }
    }

    /// save performs one explicit transaction after validating the complete prior generation.
    /// Rollback discards unsaved context changes; it makes no claim about physical file growth.
    func save(
        _ generation              : SwiftDataArchiveGeneration,
        replacing expectedRevision: UInt64?,
        identity                  : VerifiedAddonIdentity,
        beforeCommit              : @Sendable () throws -> Void
    ) throws {
        guard !Thread.isMainThread else { throw SwiftDataArchiveFailure.unavailable }
        try autoreleasepool {
            let context = operationContext()
            do {
                let existing = try row(in: context)
                let previous = try existing.map {
                    try validate(
                        $0,
                        identity: identity
                    )
                }
                guard previous?.revision == expectedRevision,
                      generation.revision > (previous?.revision ?? 0) else {
                    throw SwiftDataArchiveFailure.staleRevision
                }
                if let existing {
                    existing.schemaVersion  = generation.schemaVersion
                    existing.revision       = String(generation.revision)
                    existing.verifiedDigest = generation.verifiedDigest
                    existing.payload        = generation.payload
                    existing.checksum       = Self.checksum(
                        identity  : identity,
                        generation: generation
                    )
                } else {
                    context.insert(SwiftDataArchiveRow(
                        identity  : identity,
                        generation: generation
                    ))
                }
                try beforeCommit()
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    /// operationContext owns no undo/autosave work and never escapes one synchronous operation.
    private func operationContext() -> ModelContext {
        let context             = ModelContext(modelContainer)
        context.autosaveEnabled = false
        context.undoManager     = nil
        return context
    }

    /// row rejects a multi-row store rather than selecting a plausible partial generation.
    private func row(in context: ModelContext) throws -> SwiftDataArchiveRow? {
        var descriptor        = FetchDescriptor<SwiftDataArchiveRow>()
        descriptor.fetchLimit = 2
        let rows              = try context.fetch(descriptor)
        guard rows.count <= 1 else { throw SwiftDataArchiveFailure.corrupt }
        return rows.first
    }

    /// validate treats persisted identity and checksum as data, never as host-issued authority.
    private func validate(
        _ row   : SwiftDataArchiveRow,
        identity: VerifiedAddonIdentity
    ) throws -> SwiftDataArchiveGeneration {
        guard row.formatVersion <= 1, row.schemaVersion <= 1 else {
            throw SwiftDataArchiveFailure.futureFormat
        }
        guard row.formatVersion == 1,
              row.namespace == Self.namespace(identity),
              row.publisher == identity.publisher,
              row.addonID == identity.addonID.rawValue,
              row.revision.utf8.count <= 20,
              let revision = UInt64(row.revision),
              String(revision) == row.revision else {
            throw SwiftDataArchiveFailure.corrupt
        }
        let generation = SwiftDataArchiveGeneration(
            schemaVersion : row.schemaVersion,
            revision      : revision,
            verifiedDigest: row.verifiedDigest,
            payload       : row.payload
        )
        try generation.validate()
        guard row.checksum == Self.checksum(
            identity  : identity,
            generation: generation
        ) else { throw SwiftDataArchiveFailure.corrupt }
        return generation
    }

    /// namespace uses the existing byte-exact verified-owner digest without executable versioning.
    nonisolated static func namespace(_ identity: VerifiedAddonIdentity) -> String {
        KeyedStorageRecord.hex(KeyedStorageRecord.namespaceDigest(identity))
    }

    /// checksum authenticates record consistency, not an untrusted publisher claim.
    /// Field lengths delimit checksum input only; raw payload is hashed without reencoding.
    nonisolated static func checksum(
        identity  : VerifiedAddonIdentity,
        generation: SwiftDataArchiveGeneration
    ) -> Data {
        var hash = SHA256()
        hash.update(data: Data("Cascade.swiftdata.archive.v1\0".utf8))
        for field in [
            identity.publisher, identity.addonID.rawValue,
            String(generation.schemaVersion), String(generation.revision), generation.verifiedDigest
        ] {
            hash.update(data: Data(String(field.utf8.count).utf8))
            hash.update(data: Data([0]))
            hash.update(data: Data(field.utf8))
        }
        hash.update(data: generation.payload)
        return Data(hash.finalize())
    }
}
