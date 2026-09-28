//
//  FileWorkspaceStore.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import UniformTypeIdentifiers

/// FileWorkspaceStore persists ordered shelf entries and per-item delivery receipts.
actor FileWorkspaceStore {
    nonisolated let namespaceLifetime: FileWorkspaceNamespaceLifetime
    nonisolated let writerID = UUID()

    private static let manifestVersion = 1
    private static let copyChunkBytes   = 64 * 1_024
    private static let atomicOverhead   = 4_096

    private struct Manifest: Codable, Sendable {
        let version : Int
        var revision: UInt64
        var entries : [StoredEntry]
    }

    private struct StoredReference: Codable, Equatable, Sendable {
        var bookmark: Data
        let identity: FileReferenceIdentity
    }

    private struct StoredEntry: Codable, Equatable, Sendable {
        let id            : UUID
        let name          : String
        let typeIdentifier: String
        let ownership     : FileOwnership
        var reference     : StoredReference?
        let managedName   : String?
        let identity      : FileReferenceIdentity
        let generation    : UUID?
    }

    private struct Delivery: Sendable {
        var pending: [UUID: StoredEntry]
    }

    private struct Inventory: Sendable {
        let bytes     : Int
        let isComplete: Bool
    }

    private struct Cursor: Codable {
        let revision: UInt64
        let offset  : Int
    }

    private let directory  : URL
    private let owner      : AddonID
    private let resources  : any RuntimeResourceAccess
    private let persistence: any FileWorkspacePersisting
    private let references : any FileReferenceResolving

    private var manifest = Manifest(
        version : manifestVersion,
        revision: 0,
        entries : []
    )
    private var deliveries: [UUID: Delivery] = [:]
    private var managedPins: [String: Int] = [:]
    private var manifestBytes = 0
    private var deliveryRetainedBytes = 0
    private var active : UUID?
    private var restored = false
    private var blocked  = false

    init(
        directory  : URL,
        owner      : AddonID,
        resources  : any RuntimeResourceAccess,
        persistence: any FileWorkspacePersisting,
        references : any FileReferenceResolving,
        lifetime   : FileWorkspaceNamespaceLifetime
    ) {
        let canonical = directory.standardizedFileURL
        self.directory   = canonical
        self.owner       = owner
        self.resources   = resources
        self.persistence = persistence
        self.references  = references
        namespaceLifetime = lifetime
    }

    /// restore accounts every retained file before decoding and never repairs unknown data.
    func restore() async throws {
        try await withOperation(restoring: true) { operation in
            do {
                try FileWorkspacePath.validatePrivateDirectory(self.directory)
                let inventory = self.inventory()
                try await self.namespaceLifetime.establish(
                    measuredBytes: inventory.bytes,
                    operation    : operation
                )
                guard inventory.isComplete else { throw FileWorkspaceError.ioFailure }
                let loaded     : Manifest
                let loadedBytes: Int
                if let data = try await self.persistence.load() {
                    loaded = try JSONDecoder().decode(Manifest.self, from: data)
                    try self.validate(loaded)
                    loadedBytes = data.count
                } else {
                    loaded = Manifest(
                        version : Self.manifestVersion,
                        revision: 0,
                        entries : []
                    )
                    loadedBytes = try JSONEncoder().encode(loaded).count
                }
                try await self.namespaceLifetime.accountRetained(
                    bytes    : try Self.retainedManifestBytes(
                        encodedBytes: loadedBytes,
                        entryCount  : loaded.entries.count
                    ),
                    operation: operation
                )
                try self.ensureManagedDirectories()
                try await self.namespaceLifetime.activate(
                    writer   : self.writerID,
                    operation: operation
                )
                self.manifest   = loaded
                self.deliveries = [:]
                self.managedPins = [:]
                self.manifestBytes = try Self.retainedManifestBytes(
                    encodedBytes: loadedBytes,
                    entryCount  : loaded.entries.count
                )
                self.deliveryRetainedBytes = 0
                self.restored   = true
                self.blocked    = false
            } catch {
                self.blocked = true
                throw Self.map(error)
            }
        }
    }

    /// close relinquishes the sole live writer only when no delivery still borrows bytes.
    func close() async throws {
        try await withOperation { operation in
            guard self.deliveries.isEmpty, self.managedPins.isEmpty else {
                throw FileWorkspaceError.interrupted
            }
            try await self.namespaceLifetime.close(
                writer   : self.writerID,
                operation: operation
            )
            self.manifest = Manifest(
                version : Self.manifestVersion,
                revision: 0,
                entries : []
            )
            self.deliveries = [:]
            self.managedPins = [:]
            self.manifestBytes = 0
            self.deliveryRetainedBytes = 0
            self.restored = false
            self.blocked  = true
        }
    }

    /// addOriginals stores bookmarks and stable identities without copying file contents.
    func addOriginals(_ urls: [URL]) async throws -> [UUID] {
        try await withOperation { operation in
            try self.requireWritable()
            var candidate = self.manifest
            var known = Dictionary(
                uniqueKeysWithValues: candidate.entries.map { ($0.identity, $0.id) }
            )
            var ids: [UUID] = []
            for url in urls {
                let lease: FileReferenceLease
                do { lease = try await self.references.createReference(to: url) }
                catch { throw FileWorkspaceError.unsupported }
                defer { lease.close() }
                if let existing = known[lease.identity] {
                    if !ids.contains(existing) { ids.append(existing) }
                    continue
                }
                let metadata = try Self.metadata(for: lease.url)
                let id = UUID()
                candidate.entries.append(
                    StoredEntry(
                        id            : id,
                        name          : metadata.name,
                        typeIdentifier: metadata.type,
                        ownership     : .externalReference,
                        reference     : StoredReference(
                            bookmark: lease.bookmark,
                            identity: lease.identity
                        ),
                        managedName: nil,
                        identity   : lease.identity,
                        generation : UUID()
                    )
                )
                known[lease.identity] = id
                ids.append(id)
            }
            guard candidate.entries != self.manifest.entries else { return ids }
            candidate.revision = try Self.nextRevision(self.manifest.revision)
            try await self.commit(candidate, operation: operation)
            return ids
        }
    }

    /// importPromisedFile bounds a managed copy of an already-completed host-authorized input.
    func importPromisedFile(_ url: URL) async throws -> UUID {
        try await withOperation { operation in
            try self.requireWritable()
            let source: FileReferenceLease
            do { source = try await self.references.createReference(to: url) }
            catch { throw FileWorkspaceError.unsupported }
            defer { source.close() }
            let metadata = try Self.metadata(for: source.url)
            let id        = UUID()
            let name      = id.uuidString
            let output: FileReferenceIdentity
            do {
                output = try await self.copyToStaging(
                    source   : source,
                    name     : name,
                    operation: operation
                )
            } catch {
                try? await self.reconcile(operation: operation)
                throw Self.map(error)
            }
            do {
                try self.publishStaging(name: name)
                let measured = self.inventory()
                try await self.namespaceLifetime.reconcile(
                    measuredBytes: measured.bytes,
                    mayRefund    : measured.isComplete,
                    operation    : operation
                )
                var candidate = self.manifest
                candidate.entries.append(
                    StoredEntry(
                        id            : id,
                        name          : metadata.name,
                        typeIdentifier: metadata.type,
                        ownership     : .managed,
                        reference     : nil,
                        managedName   : name,
                        identity      : output,
                        generation    : UUID()
                    )
                )
                candidate.revision = try Self.nextRevision(self.manifest.revision)
                try await self.commit(candidate, operation: operation)
                return id
            } catch {
                if error is FileWorkspaceCommitUncertain { throw FileWorkspaceError.ioFailure }
                self.removeOwnedFile(
                    directory       : "managed",
                    name            : name,
                    expectedIdentity: output
                )
                try? await self.reconcile(operation: operation)
                throw Self.map(error)
            }
        }
    }

    /// snapshot returns one revision-bound page and refreshes only identity-preserving bookmarks.
    func snapshot(
        cursor  : String?,
        pageSize: Int = 32
    ) async throws -> FileWorkspaceSnapshot {
        try await withOperation { operation in
            try self.requireRestored()
            guard (1...32).contains(pageSize) else { throw FileWorkspaceError.unsupported }
            let offset = try self.decodeCursor(cursor)
            guard offset <= self.manifest.entries.count else { throw FileWorkspaceError.staleRevision }
            var refreshed = self.manifest
            var page: [FileWorkspaceEntry] = []
            var index = offset
            while index < refreshed.entries.count, page.count < pageSize {
                let value = try await self.project(
                    entry    : refreshed.entries[index],
                    refreshed: &refreshed.entries[index]
                )
                let proposed = page + [value]
                let next = index + 1 < refreshed.entries.count
                    ? try self.encodeCursor(offset: index + 1) : nil
                let candidate = try FileWorkspaceSnapshot(
                    revision  : refreshed.revision,
                    entries   : proposed,
                    totalCount: refreshed.entries.count,
                    nextCursor: next,
                    jobs      : []
                )
                do { _ = try candidate.encode() }
                catch { break }
                page = proposed
                index += 1
            }
            guard offset == refreshed.entries.count || !page.isEmpty else {
                throw FileWorkspaceError.ioFailure
            }
            if refreshed.entries != self.manifest.entries {
                try await self.commit(refreshed, operation: operation)
            }
            return try FileWorkspaceSnapshot(
                revision  : self.manifest.revision,
                entries   : page,
                totalCount: self.manifest.entries.count,
                nextCursor: index < self.manifest.entries.count
                    ? try self.encodeCursor(offset: index) : nil,
                jobs      : []
            )
        }
    }

    /// prepareItems captures immutable lifetimes for deferred native file-promise callbacks.
    func prepareItems(ids: [UUID]) async throws -> [FileWorkspacePreparedEntry] {
        try await withOperation { _ in
            try self.requireWritable()
            guard !ids.isEmpty, ids.count <= 32, Set(ids).count == ids.count else {
                throw FileWorkspaceError.unsupported
            }
            let byID = Dictionary(uniqueKeysWithValues: self.manifest.entries.map { ($0.id, $0) })
            return try ids.map { id in
                guard let entry = byID[id] else { throw FileWorkspaceError.unavailable }
                return self.prepared(entry)
            }
        }
    }

    /// prepareAllItems is prepareItems over the whole manifest, in shelf order.
    /// It reads only in-memory records: the shelf learns its size and its
    /// whole-deck drag set without resolving a single bookmark. Availability
    /// is still checked where it matters, when a delivery begins.
    func prepareAllItems() async throws -> [FileWorkspacePreparedEntry] {
        try await withOperation { _ in
            try self.requireWritable()
            return self.manifest.entries.map(self.prepared)
        }
    }

    private func prepared(_ entry: StoredEntry) -> FileWorkspacePreparedEntry {
        FileWorkspacePreparedEntry(
            writerID      : writerID,
            id            : entry.id,
            name          : entry.name,
            typeIdentifier: entry.typeIdentifier,
            ownership     : entry.ownership,
            identity      : entry.identity,
            managedName   : entry.managedName,
            generation    : entry.generation
        )
    }

    /// beginDelivery accepts a prepared value only while its exact entry lifetime is current.
    func beginDelivery(_ prepared: FileWorkspacePreparedEntry) async throws -> UUID {
        try await withOperation { operation in
            try self.requireWritable()
            guard prepared.writerID == self.writerID,
                  let entry = self.manifest.entries.first(where: { $0.id == prepared.id }),
                  Self.sameLifetime(entry, prepared) else {
                throw FileWorkspaceError.unavailable
            }
            return try await self.beginDelivery(selected: [entry], operation: operation)
        }
    }

    /// beginDelivery pins the exact entries selected for one per-item receipt session.
    func beginDelivery(ids: [UUID]) async throws -> UUID {
        try await withOperation { operation in
            try self.requireWritable()
            guard !ids.isEmpty, ids.count <= 32, Set(ids).count == ids.count else {
                throw FileWorkspaceError.unsupported
            }
            let byID = Dictionary(uniqueKeysWithValues: self.manifest.entries.map { ($0.id, $0) })
            let selected = try ids.map { id -> StoredEntry in
                guard let entry = byID[id] else { throw FileWorkspaceError.unavailable }
                return entry
            }
            return try await self.beginDelivery(selected: selected, operation: operation)
        }
    }

    /// lease resolves a prepared lifetime for a host-scoped preview or reveal operation.
    func lease(for prepared: FileWorkspacePreparedEntry) async throws -> FileReferenceLease {
        try await withOperation { _ in
            try self.requireWritable()
            guard prepared.writerID == self.writerID,
                  let entry = self.manifest.entries.first(where: { $0.id == prepared.id }),
                  Self.sameLifetime(entry, prepared) else {
                throw FileWorkspaceError.unavailable
            }
            return try await self.lease(for: entry)
        }
    }

    /// removeExternalReference forgets a bookmark without touching the user's original file.
    func removeExternalReference(
        id      : UUID,
        revision: UInt64
    ) async throws {
        try await withOperation { operation in
            try self.requireWritable()
            guard self.manifest.revision == revision else { throw FileWorkspaceError.staleRevision }
            guard let index = self.manifest.entries.firstIndex(where: { $0.id == id }),
                  self.manifest.entries[index].ownership == .externalReference else {
                throw FileWorkspaceError.unavailable
            }
            var candidate = self.manifest
            candidate.entries.remove(at: index)
            candidate.revision = try Self.nextRevision(self.manifest.revision)
            try await self.commit(candidate, operation: operation)
        }
    }

    /// relinkExternalReference replaces a missing bookmark while preserving the row ID and order.
    func relinkExternalReference(
        id      : UUID,
        to url  : URL,
        revision: UInt64
    ) async throws {
        try await withOperation { operation in
            try self.requireWritable()
            guard self.manifest.revision == revision else { throw FileWorkspaceError.staleRevision }
            guard let index = self.manifest.entries.firstIndex(where: { $0.id == id }),
                  self.manifest.entries[index].ownership == .externalReference else {
                throw FileWorkspaceError.unavailable
            }
            let lease: FileReferenceLease
            do { lease = try await self.references.createReference(to: url) }
            catch { throw FileWorkspaceError.unsupported }
            defer { lease.close() }
            guard !self.manifest.entries.enumerated().contains(where: {
                $0.offset != index && $0.element.identity == lease.identity
            }) else { throw FileWorkspaceError.unsupported }
            let metadata = try Self.metadata(for: lease.url)
            var candidate = self.manifest
            candidate.entries[index] = StoredEntry(
                id            : id,
                name          : metadata.name,
                typeIdentifier: metadata.type,
                ownership     : .externalReference,
                reference     : StoredReference(
                    bookmark: lease.bookmark,
                    identity: lease.identity
                ),
                managedName: nil,
                identity   : lease.identity,
                generation : UUID()
            )
            candidate.revision = try Self.nextRevision(self.manifest.revision)
            try await self.commit(candidate, operation: operation)
        }
    }

    /// renameExternalReference renames the original in its current directory and refreshes the
    /// durable bookmark.
    func renameExternalReference(id: UUID, newName: String, revision: UInt64) async throws {
        try await withOperation { operation in
            try self.requireWritable()
            guard self.manifest.revision == revision else { throw FileWorkspaceError.staleRevision }
            guard !newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  newName != ".", newName != "..",
                  !newName.contains("/"), !newName.contains(":"), !newName.contains("\0"),
                  newName.utf8.count <= 255 else { throw FileWorkspaceError.unsupported }
            guard let index = self.manifest.entries.firstIndex(where: { $0.id == id }),
                  self.manifest.entries[index].ownership == .externalReference else {
                throw FileWorkspaceError.unavailable
            }
            let original = self.manifest.entries[index]
            let source = try await self.lease(for: original)
            defer { source.close() }
            guard source.url.lastPathComponent != newName else { return }
            let destination = source.url.deletingLastPathComponent().appendingPathComponent(newName)
            let metadata = try Self.metadata(for: destination)
            try Self.renameOriginal(from: source.url, to: destination, identity: source.identity)
            do {
                let renamed = try await self.references.createReference(to: destination)
                defer { renamed.close() }
                guard renamed.identity == source.identity else { throw FileWorkspaceError.unavailable }
                var candidate = self.manifest
                candidate.entries[index] = StoredEntry(
                    id: id, name: metadata.name, typeIdentifier: metadata.type,
                    ownership: .externalReference,
                    reference: StoredReference(bookmark: renamed.bookmark, identity: renamed.identity),
                    managedName: nil, identity: renamed.identity, generation: UUID()
                )
                candidate.revision = try Self.nextRevision(self.manifest.revision)
                try await self.commit(candidate, operation: operation)
            } catch {
                // Once persistence may have committed, its new bookmark remains authoritative.
                if !(error is FileWorkspaceCommitUncertain), self.manifest.revision == revision {
                    try? Self.renameOriginal(from: destination, to: source.url, identity: source.identity)
                }
                throw Self.map(error)
            }
        }
    }

    private static func renameOriginal(
        from source: URL, to destination: URL, identity: FileReferenceIdentity
    ) throws {
        var coordinationError: NSError?
        var failure: (any Error)?
        NSFileCoordinator().coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: destination, options: [], error: &coordinationError
        ) { sourceURL, destinationURL in
            var info = stat()
            guard lstat(sourceURL.path, &info) == 0,
                  info.st_mode & S_IFMT == S_IFREG,
                  UInt64(info.st_dev) == identity.device,
                  UInt64(info.st_ino) == identity.inode,
                  UInt64(info.st_gen) == identity.generation else {
                failure = FileWorkspaceError.unavailable
                return
            }
            // RENAME_EXCL performs an atomic no-overwrite move in the same directory.
            guard renameatx_np(AT_FDCWD, sourceURL.path, AT_FDCWD, destinationURL.path, UInt32(RENAME_EXCL)) == 0 else {
                failure = (errno == EACCES || errno == EPERM)
                    ? FileWorkspaceError.permissionDenied : FileWorkspaceError.ioFailure
                return
            }
        }
        if let failure { throw failure }
        if coordinationError != nil { throw FileWorkspaceError.ioFailure }
    }

    /// leaseForDelivery keeps the checked descriptor and any security scope alive for the reader.
    /// The returned URL is metadata; delivery code reads from the descriptor to avoid path replacement.
    func leaseForDelivery(
        _ deliveryID: UUID,
        itemID      : UUID
    ) async throws -> FileReferenceLease {
        try await withOperation { _ in
            try self.requireWritable()
            guard let entry = self.deliveries[deliveryID]?.pending[itemID] else {
                throw FileWorkspaceError.unavailable
            }
            return try await self.lease(for: entry)
        }
    }

    /// finishDelivery persists a successful item's removal before releasing its retained file pin.
    func finishDelivery(
        _ deliveryID: UUID,
        itemID      : UUID,
        result      : Result<Void, FileWorkspaceError>
    ) async throws {
        try await withOperation { operation in
            switch result {
            case .success:
                try self.requireWritable()
            case .failure:
                guard self.restored else { throw FileWorkspaceError.ioFailure }
            }
            guard var delivery = self.deliveries[deliveryID],
                  let receipt = delivery.pending[itemID] else { return }
            if case .success = result,
               let index = self.manifest.entries.firstIndex(where: {
                   Self.sameLifetime($0, receipt)
               }) {
                var candidate = self.manifest
                candidate.entries.remove(at: index)
                candidate.revision = try Self.nextRevision(self.manifest.revision)
                try await self.commit(candidate, operation: operation)
            }
            delivery.pending.removeValue(forKey: itemID)
            let retained = ((try? JSONEncoder().encode(receipt).count) ?? 0) + 256
            self.deliveryRetainedBytes = max(0, self.deliveryRetainedBytes - retained)
            if delivery.pending.isEmpty { self.deliveries.removeValue(forKey: deliveryID) }
            else { self.deliveries[deliveryID] = delivery }
            if let name = receipt.managedName {
                self.managedPins[name, default: 1] -= 1
                if self.managedPins[name] == 0 { self.managedPins.removeValue(forKey: name) }
            }
            try await self.namespaceLifetime.releaseDeliveryPin(
                writer   : self.writerID,
                operation: operation
            )
            if let name = receipt.managedName,
               self.managedPins[name] == nil,
               !self.manifest.entries.contains(where: { $0.managedName == name }) {
                self.removeOwnedFile(
                    directory      : "managed",
                    name           : name,
                    expectedIdentity: receipt.identity
                )
                try await self.reconcile(operation: operation)
            }
            try? await self.namespaceLifetime.accountRetained(
                bytes    : self.manifestBytes + self.deliveryRetainedBytes,
                operation: operation
            )
        }
    }

    /// removeManaged deletes the only managed copy only with the host's typed confirmation.
    func removeManaged(
        id                    : UUID,
        confirmingDestruction: FileWorkspaceManagedRemovalConfirmation
    ) async throws {
        try await withOperation { operation in
            try self.requireWritable()
            guard let index = self.manifest.entries.firstIndex(where: { $0.id == id }),
                  self.manifest.entries[index].ownership == .managed,
                  let name = self.manifest.entries[index].managedName else {
                throw FileWorkspaceError.unavailable
            }
            guard confirmingDestruction == .deleteOnlyManagedCopy else {
                throw FileWorkspaceError.permissionDenied
            }
            let removed = self.manifest.entries[index]
            var candidate = self.manifest
            candidate.entries.remove(at: index)
            candidate.revision = try Self.nextRevision(self.manifest.revision)
            try await self.commit(candidate, operation: operation)
            if self.managedPins[name, default: 0] == 0 {
                self.removeOwnedFile(
                    directory      : "managed",
                    name           : name,
                    expectedIdentity: removed.identity
                )
                try await self.reconcile(operation: operation)
            }
        }
    }

    private func beginDelivery(
        selected : [StoredEntry],
        operation: UUID
    ) async throws -> UUID {
        let retained = try selected.reduce(into: 0) { total, entry in
            let count = try JSONEncoder().encode(entry).count + 256
            let next  = total.addingReportingOverflow(count)
            guard !next.overflow else { throw FileWorkspaceError.quotaExceeded }
            total = next.partialValue
        }
        try await namespaceLifetime.accountRetained(
            bytes    : manifestBytes + deliveryRetainedBytes + retained,
            operation: operation
        )
        do {
            try await namespaceLifetime.addDeliveryPins(
                selected.count,
                writer   : writerID,
                operation: operation
            )
        } catch {
            try? await namespaceLifetime.accountRetained(
                bytes    : manifestBytes + deliveryRetainedBytes,
                operation: operation
            )
            throw error
        }
        var pending: [UUID: StoredEntry] = [:]
        for entry in selected {
            pending[entry.id] = entry
            if let name = entry.managedName { managedPins[name, default: 0] += 1 }
        }
        let deliveryID = UUID()
        deliveries[deliveryID] = Delivery(pending: pending)
        deliveryRetainedBytes += retained
        return deliveryID
    }

    private func lease(for entry: StoredEntry) async throws -> FileReferenceLease {
        switch entry.ownership {
        case .externalReference:
            guard let reference = entry.reference else { throw FileWorkspaceError.ioFailure }
            let lease = try await references.resolve(reference.bookmark)
            guard lease.identity == reference.identity else {
                lease.close()
                throw FileWorkspaceError.unavailable
            }
            return lease
        case .managed:
            guard let name = entry.managedName else { throw FileWorkspaceError.ioFailure }
            return try managedLease(name: name, identity: entry.identity)
        }
    }

    private func withOperation<Result: Sendable>(
        restoring: Bool = false,
        _ body: (UUID) async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        guard active == nil else { throw FileWorkspaceError.interrupted }
        let operation = UUID()
        active = operation
        do {
            try await namespaceLifetime.begin(
                operation,
                directory: directory,
                owner    : owner,
                governor : resources.resourceGovernorTarget,
                writer   : writerID,
                restoring: restoring
            )
        } catch {
            active = nil
            throw Self.map(error)
        }
        do {
            let result = try await body(operation)
            await namespaceLifetime.finish(operation)
            active = nil
            return result
        } catch {
            await namespaceLifetime.finish(operation)
            active = nil
            throw Self.map(error)
        }
    }

    /// commit publishes immediately after the persistence commit point. Reconciliation failure
    /// faults later mutations but cannot roll back or clean bytes named by the durable manifest.
    private func commit(
        _ candidate: Manifest,
        operation  : UUID
    ) async throws {
        let data = try JSONEncoder().encode(candidate)
        let candidateManifestBytes = try Self.retainedManifestBytes(
            encodedBytes: data.count,
            entryCount  : candidate.entries.count
        )
        let previousRetained  = manifestBytes + deliveryRetainedBytes
        let candidateRetained = candidateManifestBytes + deliveryRetainedBytes
        try await namespaceLifetime.accountRetained(
            bytes    : max(previousRetained, candidateRetained),
            operation: operation
        )
        try await namespaceLifetime.grow(
            additionalBytes: data.count + Self.atomicOverhead,
            operation      : operation
        )
        do { try await persistence.save(data) }
        catch FileWorkspacePersistenceFailure.commitUncertain {
            blocked = true
            throw FileWorkspaceCommitUncertain()
        } catch {
            try? await namespaceLifetime.accountRetained(
                bytes    : previousRetained,
                operation: operation
            )
            try? await reconcile(operation: operation)
            throw FileWorkspaceError.ioFailure
        }
        manifest = candidate
        manifestBytes = candidateManifestBytes
        do {
            try await namespaceLifetime.accountRetained(
                bytes    : candidateRetained,
                operation: operation
            )
            try await reconcile(operation: operation)
        }
        catch { blocked = true }
    }

    private func reconcile(operation: UUID) async throws {
        let measured = inventory()
        try await namespaceLifetime.reconcile(
            measuredBytes: measured.bytes,
            mayRefund    : measured.isComplete,
            operation    : operation
        )
    }

    private func validate(_ value: Manifest) throws {
        guard value.version == Self.manifestVersion,
              Set(value.entries.map(\.id)).count == value.entries.count,
              Set(value.entries.map(\.identity)).count == value.entries.count else {
            throw FileWorkspaceError.ioFailure
        }
        for entry in value.entries {
            _ = try FileWorkspaceEntry(
                id              : entry.id,
                name            : entry.name,
                typeIdentifier  : entry.typeIdentifier,
                availability    : .available,
                ownership       : entry.ownership,
                thumbnailAssetID: nil
            )
            switch entry.ownership {
            case .externalReference:
                guard entry.reference?.identity == entry.identity,
                      entry.managedName == nil else { throw FileWorkspaceError.ioFailure }
            case .managed:
                guard entry.reference == nil,
                      let name = entry.managedName,
                      name == entry.id.uuidString,
                      !name.contains("/") else { throw FileWorkspaceError.ioFailure }
            }
        }
    }

    private func project(
        entry    : StoredEntry,
        refreshed: inout StoredEntry
    ) async throws -> FileWorkspaceEntry {
        let availability: FileAvailability
        switch entry.ownership {
        case .externalReference:
            guard let reference = entry.reference else { throw FileWorkspaceError.ioFailure }
            do {
                let lease = try await references.resolve(reference.bookmark)
                defer { lease.close() }
                if lease.identity == reference.identity {
                    availability = .available
                    if lease.bookmark != reference.bookmark {
                        refreshed.reference = StoredReference(
                            bookmark: lease.bookmark,
                            identity: reference.identity
                        )
                    }
                } else {
                    availability = .unavailable
                }
            } catch {
                availability = .unavailable
            }
        case .managed:
            availability = managedIdentity(name: entry.managedName) == entry.identity
                ? .available : .unavailable
        }
        return try FileWorkspaceEntry(
            id              : entry.id,
            name            : entry.name,
            typeIdentifier  : entry.typeIdentifier,
            availability    : availability,
            ownership       : entry.ownership,
            thumbnailAssetID: nil
        )
    }

    private func decodeCursor(_ value: String?) throws -> Int {
        guard let value else { return 0 }
        guard let data = Data(base64Encoded: value),
              let cursor = try? JSONDecoder().decode(Cursor.self, from: data),
              cursor.revision == manifest.revision,
              cursor.offset >= 0 else { throw FileWorkspaceError.staleRevision }
        return cursor.offset
    }

    private func encodeCursor(offset: Int) throws -> String {
        try JSONEncoder().encode(
            Cursor(
                revision: manifest.revision,
                offset  : offset
            )
        ).base64EncodedString()
    }

    private func ensureManagedDirectories() throws {
        let root = try openRoot()
        defer { Darwin.close(root) }
        for name in ["managed", "staging"] {
            if mkdirat(root, name, 0o700) != 0, errno != EEXIST {
                throw FileWorkspaceError.ioFailure
            }
            let child = openat(root, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard child >= 0 else { throw FileWorkspaceError.ioFailure }
            var info = stat()
            let valid = fstat(child, &info) == 0
                && info.st_mode & S_IFMT == S_IFDIR
                && info.st_uid == getuid()
                && info.st_mode & 0o7777 == 0o700
            Darwin.close(child)
            guard valid else { throw FileWorkspaceError.ioFailure }
        }
    }

    private func copyToStaging(
        source   : FileReferenceLease,
        name     : String,
        operation: UUID
    ) async throws -> FileReferenceIdentity {
        let root = try openRoot()
        defer { Darwin.close(root) }
        let staging = openat(root, "staging", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard staging >= 0 else { throw FileWorkspaceError.ioFailure }
        defer { Darwin.close(staging) }
        let part = name + ".part"
        let output = openat(
            staging,
            part,
            O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC,
            mode_t(0o600)
        )
        guard output >= 0 else { throw FileWorkspaceError.ioFailure }
        var keep = true
        defer {
            Darwin.close(output)
            if keep { _ = unlinkat(staging, part, 0) }
        }
        var buffer = Data(count: Self.copyChunkBytes)
        while true {
            let count = try buffer.withUnsafeMutableBytes { bytes -> Int in
                guard let base = bytes.baseAddress else { return 0 }
                while true {
                    let read = Darwin.read(source.descriptor, base, bytes.count)
                    if read < 0, errno == EINTR { continue }
                    guard read >= 0 else { throw FileWorkspaceError.ioFailure }
                    return read
                }
            }
            if count == 0 { break }
            try await namespaceLifetime.grow(
                additionalBytes: count,
                operation      : operation
            )
            try buffer.withUnsafeBytes { bytes in
                guard let base = bytes.baseAddress else { return }
                var offset = 0
                while offset < count {
                    let wrote = Darwin.write(output, base.advanced(by: offset), count - offset)
                    if wrote < 0, errno == EINTR { continue }
                    guard wrote > 0 else { throw FileWorkspaceError.ioFailure }
                    offset += wrote
                }
            }
        }
        guard fsync(output) == 0 else { throw FileWorkspaceError.ioFailure }
        var info = stat()
        guard fstat(output, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid() else { throw FileWorkspaceError.ioFailure }
        keep = false
        return FileReferenceIdentity(
            device    : UInt64(info.st_dev),
            inode     : UInt64(info.st_ino),
            generation: UInt64(info.st_gen)
        )
    }

    private func publishStaging(name: String) throws {
        let root = try openRoot()
        defer { Darwin.close(root) }
        let staging = openat(root, "staging", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        let managed = openat(root, "managed", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard staging >= 0, managed >= 0 else {
            if staging >= 0 { Darwin.close(staging) }
            if managed >= 0 { Darwin.close(managed) }
            throw FileWorkspaceError.ioFailure
        }
        defer { Darwin.close(staging); Darwin.close(managed) }
        guard renameatx_np(
            staging,
            name + ".part",
            managed,
            name,
            UInt32(RENAME_EXCL)
        ) == 0 else {
            throw FileWorkspaceError.ioFailure
        }
        guard fsync(managed) == 0, fsync(staging) == 0 else {
            throw FileWorkspaceError.ioFailure
        }
    }

    private func removeOwnedFile(
        directory       childName: String,
        name                      : String,
        expectedIdentity          : FileReferenceIdentity?
    ) {
        guard let expectedIdentity, !name.contains("/"), let root = try? openRoot() else { return }
        defer { Darwin.close(root) }
        let child = openat(root, childName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard child >= 0 else { return }
        defer { Darwin.close(child) }
        let file = openat(child, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else { return }
        var info = stat()
        let identity = fstat(file, &info) == 0 ? FileReferenceIdentity(
            device    : UInt64(info.st_dev),
            inode     : UInt64(info.st_ino),
            generation: UInt64(info.st_gen)
        ) : nil
        Darwin.close(file)
        guard identity == expectedIdentity else { return }
        _ = unlinkat(child, name, 0)
        _ = fsync(child)
    }

    private func managedIdentity(name: String?) -> FileReferenceIdentity? {
        guard let name, !name.contains("/"), let root = try? openRoot() else { return nil }
        defer { Darwin.close(root) }
        let managed = openat(root, "managed", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard managed >= 0 else { return nil }
        defer { Darwin.close(managed) }
        let descriptor = openat(managed, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_uid == getuid() else { return nil }
        return FileReferenceIdentity(
            device    : UInt64(info.st_dev),
            inode     : UInt64(info.st_ino),
            generation: UInt64(info.st_gen)
        )
    }

    private func managedLease(
        name    : String,
        identity: FileReferenceIdentity
    ) throws -> FileReferenceLease {
        guard !name.contains("/") else { throw FileWorkspaceError.ioFailure }
        let root = try openRoot()
        defer { Darwin.close(root) }
        let managed = openat(root, "managed", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard managed >= 0 else { throw FileWorkspaceError.unavailable }
        defer { Darwin.close(managed) }
        let descriptor = openat(managed, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw FileWorkspaceError.unavailable }
        var info = stat()
        let actual = fstat(descriptor, &info) == 0 ? FileReferenceIdentity(
            device    : UInt64(info.st_dev),
            inode     : UInt64(info.st_ino),
            generation: UInt64(info.st_gen)
        ) : nil
        guard actual == identity else {
            Darwin.close(descriptor)
            throw FileWorkspaceError.unavailable
        }
        return FileReferenceLease(
            url       : directory.appendingPathComponent("managed/\(name)"),
            bookmark  : Data(),
            identity  : identity,
            descriptor: descriptor,
            scoped    : false
        )
    }

    private func openRoot() throws -> Int32 {
        try FileWorkspacePath.validatePrivateDirectory(directory)
        let descriptor = Darwin.open(
            directory.path,
            O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC
        )
        guard descriptor >= 0 else { throw FileWorkspaceError.ioFailure }
        return descriptor
    }

    private func inventory() -> Inventory {
        var bytes = 0
        var complete = true
        guard let enumerator = FileManager.default.enumerator(
            at                : directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
            options           : [],
            errorHandler      : { _, _ in complete = false; return false }
        ) else { return Inventory(bytes: 0, isComplete: false) }
        for case let url as URL in enumerator {
            do {
                let values = try url.resourceValues(
                    forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey]
                )
                if values.isSymbolicLink == true {
                    enumerator.skipDescendants()
                    complete = false
                } else if values.isRegularFile == true, let size = values.fileSize, size >= 0 {
                    let total = bytes.addingReportingOverflow(size)
                    guard !total.overflow else { return Inventory(bytes: Int.max, isComplete: false) }
                    bytes = total.partialValue
                } else if values.isDirectory != true {
                    complete = false
                }
            } catch {
                complete = false
            }
        }
        return Inventory(bytes: bytes, isComplete: complete)
    }

    private func requireRestored() throws {
        guard restored, !blocked else { throw FileWorkspaceError.ioFailure }
    }

    private func requireWritable() throws { try requireRestored() }

    private static func metadata(for url: URL) throws -> (name: String, type: String) {
        let name = url.lastPathComponent
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.utf8.count <= 4_096 else { throw FileWorkspaceError.unsupported }
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]).contentType?.identifier)
            ?? UTType(filenameExtension: url.pathExtension)?.identifier
            ?? UTType.data.identifier
        return (name, type)
    }

    private static func nextRevision(_ revision: UInt64) throws -> UInt64 {
        let next = revision.addingReportingOverflow(1)
        guard !next.overflow else { throw FileWorkspaceError.ioFailure }
        return next.partialValue
    }

    private static func retainedManifestBytes(
        encodedBytes: Int,
        entryCount  : Int
    ) throws -> Int {
        let overhead = entryCount.multipliedReportingOverflow(by: 256)
        guard !overhead.overflow else { throw FileWorkspaceError.quotaExceeded }
        let total = encodedBytes.addingReportingOverflow(overhead.partialValue)
        guard !total.overflow else { throw FileWorkspaceError.quotaExceeded }
        return total.partialValue
    }

    private static func sameLifetime(
        _ lhs: StoredEntry,
        _ rhs: StoredEntry
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.ownership == rhs.ownership
            && lhs.identity == rhs.identity
            && lhs.managedName == rhs.managedName
            && lhs.generation == rhs.generation
    }

    private static func sameLifetime(
        _ lhs: StoredEntry,
        _ rhs: FileWorkspacePreparedEntry
    ) -> Bool {
        lhs.id == rhs.id
            && lhs.ownership == rhs.ownership
            && lhs.identity == rhs.identity
            && lhs.managedName == rhs.managedName
            && lhs.generation == rhs.generation
    }

    private static func map(_ error: any Error) -> FileWorkspaceError {
        if let error = error as? FileWorkspaceError { return error }
        if error is CancellationError { return .interrupted }
        if let error = error as? AddonFailure, error.code == .resourceDenied { return .quotaExceeded }
        return .ioFailure
    }
}
