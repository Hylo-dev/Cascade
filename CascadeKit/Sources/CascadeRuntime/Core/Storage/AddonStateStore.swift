//
//  AddonStateStore.swift
//  CascadeKit
//

import CascadeContracts
import CryptoKit
import Darwin
import Foundation

/// AddonStateStore provides bounded checkpoint persistence. All filesystem work runs on this actor,
/// away from MainActor. The host must retain one instance until `close()` and supply all retained
/// identities at reopen.
public actor AddonStateStore {

    public static let maximumCheckpointBytes = 65_536
    private static let headerBytes           = 64
    private static let metadataBytes         = 4_096
    private static let operationBytes        = 4 * (maximumCheckpointBytes + headerBytes)

    private final class Namespace {

        let identity            : VerifiedAddonIdentity
        let maximumSchemaVersion: UInt32
        let name                : String

        var handle = StateOwner(id: UUID())

        var stateCharge       : ResourceReservation?
        var stageCharge       : ResourceReservation?
        var stageRetention    : ResourceReservation?
        var migrationRetention: ResourceReservation?

        var stateBytes = 0
        var stageBytes = 0

        var staged   : Staged?
        var migration: MigrationEntry?

        init(_ registration: StateRegistration) {
            let identity         = registration.identity
            self.identity        = identity
            maximumSchemaVersion = registration.maximumSchemaVersion

            let publisher = identity.publisher
            let key       = "\(publisher.utf8.count):\(publisher)\(identity.addonID.rawValue)"
            name          = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }

    private struct Staged {

        let ticket   : StateWriteTicket
        let previous : StateCheckpoint?
        let candidate: StateCheckpoint
    }

    private struct MigrationEntry {

        let ticket      : StateMigrationTicket
        let source      : StateCheckpoint
        let target      : UInt32
        var stagedTicket: StateWriteTicket?
    }

    private var rootFD    : Int32
    private let governor  : ResourceGovernor
    private let diskBudget: Int

    private var namespaces : [Namespace] = []
    private var baseCharges: [ResourceReservation] = []
    private var tableCharge: ResourceReservation?

    private var diskBytes = 0
    private var busy      = false

    private init(
        rootFD    : Int32,
        governor  : ResourceGovernor,
        diskBudget: Int
    ) {
        self.rootFD     = rootFD
        self.governor   = governor
        self.diskBudget = min(100 * 1_024 * 1_024, max(0, diskBudget))
    }

    deinit {
        if rootFD >= 0 { Darwin.close(rootFD) }
    }

    /// open requires the root to already exist, to be owned by this user and private (0700), and to
    /// have no symlink components. Unknown files fail admission. The registry includes
    /// disabled/uninstalled identities retaining data.
    public static func open(
        root          : URL,
        registrations : [StateRegistration],
        namespaceLimit: Int = 256,
        governor      : ResourceGovernor = ResourceGovernor(),
        diskBudget    : Int = 100 * 1_024 * 1_024
    ) async throws -> AddonStateStore {
        try Task.checkCancellation()
        guard !registrations.isEmpty,
              registrations.count <= min(256, max(0, namespaceLimit)),
              Set(registrations.map(\.identity)).count == registrations.count,
              registrations.allSatisfy({
                  $0.maximumSchemaVersion > 0 && !$0.identity.publisher.isEmpty
                      && $0.identity.publisher.utf8.count <= 512
              })
        else {
            throw StateStoreFailure.invalidConfiguration
        }

        // A static async function has no MainActor isolation. No provider path is accepted here.
        let descriptor = try openRoot(root)
        let store      = AddonStateStore(
            rootFD    : descriptor,
            governor  : governor,
            diskBudget: diskBudget
        )
        do {
            try await store.reconcile(registrations)
            return store
        } catch {
            try? await store.close()
            throw error
        }
    }

    public func owner(for identity: VerifiedAddonIdentity) throws -> StateOwner {
        try available()
        guard let namespace = namespaces.first(where: { $0.identity == identity }) else {
            throw StateStoreFailure.invalidOwner
        }

        return namespace.handle
    }

    public func read(owner: StateOwner) async throws -> StateCheckpoint? {
        try await perform(owner) { store, namespace in try store.readRecord(namespace, staged: false) }
    }

    public func write(
        _ data       : Data,
        schemaVersion: UInt32,
        owner        : StateOwner
    ) async throws {
        try await perform(owner) { store, namespace in
            if let previous = try store.readRecord(namespace, staged: false),
               previous.schemaVersion == schemaVersion,
               previous.data == data {
                return
            }

            let ticket = try await store.stageRecord(
                data,
                schema   : schemaVersion,
                namespace: namespace
            )
            do {
                try await store.commitRecord(ticket, namespace: namespace)
            } catch {
                try? await store.discardStage(namespace)
                throw error
            }
        }
    }

    /// stage writes prepared data to durable staging only; the previous checkpoint remains the visible value.
    public func stage(
        _ data       : Data,
        schemaVersion: UInt32,
        owner        : StateOwner
    ) async throws -> StateWriteTicket {
        try await perform(owner) { store, namespace in
            try await store.stageRecord(
                data,
                schema   : schemaVersion,
                namespace: namespace
            )
        }
    }

    public func commit(
        _ ticket: StateWriteTicket,
        owner   : StateOwner
    ) async throws {
        try await perform(owner) { store, namespace in
            try await store.commitRecord(ticket, namespace: namespace)
        }
    }

    public func cancel(
        _ ticket: StateWriteTicket,
        owner   : StateOwner
    ) async throws {
        try await perform(owner, allocatingMemory: false) { store, namespace in
            guard namespace.staged?.ticket == ticket else { throw StateStoreFailure.invalidTicket }

            try await store.discardStage(namespace)
        }
    }

    /// revoke invalidates every outstanding ticket for this identity without releasing its durable
    /// disk charge.
    public func revoke(owner: StateOwner) async throws {
        try await perform(owner, allocatingMemory: false) { store, namespace in
            namespace.handle = StateOwner(id: UUID())
            try await store.releaseMigration(namespace)
            try await store.discardStage(namespace)
        }
    }

    /// removeUserData performs explicit host/user data deletion. This API is never called by cache
    /// purging or reconnection.
    public func removeUserData(owner: StateOwner) async throws {
        try await perform(owner, allocatingMemory: false) { store, namespace in
            try await store.releaseMigration(namespace)
            try await store.discardStage(namespace)
            try store.removeFile(namespace.name + ".state")
            if let charge = namespace.stateCharge {
                try await store.governor.release(charge.id, owner: charge.owner)
            }

            store.diskBytes -= namespace.stateBytes
            namespace.stateCharge = nil
            namespace.stateBytes  = 0
            namespace.migration   = nil
        }
    }

    public func beginMigration(
        to schemaVersion: UInt32,
        owner           : StateOwner
    ) async throws -> StateMigration {
        try await perform(owner) { store, namespace in
            guard namespace.migration == nil, namespace.staged == nil else { throw StateStoreFailure.busy }
            guard let source = try store.readRecord(namespace, staged: false) else {
                throw StateStoreFailure.missingState
            }
            guard schemaVersion > source.schemaVersion,
                  schemaVersion <= namespace.maximumSchemaVersion
            else {
                throw StateStoreFailure.invalidConfiguration
            }

            let charge = try await store.governor.admit(
                .state(bytes: source.data.count + 128),
                owner: namespace.identity.addonID
            )
            do {
                try Task.checkCancellation()
            } catch {
                try await store.governor.release(charge.id, owner: charge.owner)
                throw error
            }

            let ticket                   = StateMigrationTicket(id: UUID())
            namespace.migrationRetention = charge
            namespace.migration          = MigrationEntry(
                ticket: ticket,
                source: source,
                target: schemaVersion
            )

            return StateMigration(
                ticket             : ticket,
                source             : source,
                targetSchemaVersion: schemaVersion
            )
        }
    }

    public func stageMigration(
        _ data: Data,
        ticket: StateMigrationTicket,
        owner : StateOwner
    ) async throws {
        try await perform(owner) { store, namespace in
            guard var entry = namespace.migration, entry.ticket == ticket else {
                throw StateStoreFailure.invalidTicket
            }
            guard try store.readRecord(namespace, staged: false) == entry.source else {
                throw StateStoreFailure.staleRevision
            }

            entry.stagedTicket  = try await store.stageRecord(
                data,
                schema   : entry.target,
                namespace: namespace
            )
            namespace.migration = entry
        }
    }

    public func commitMigration(
        _ ticket: StateMigrationTicket,
        owner   : StateOwner
    ) async throws {
        try await perform(owner) { store, namespace in
            guard let entry = namespace.migration,
                  entry.ticket == ticket,
                  let staged = entry.stagedTicket
            else {
                throw StateStoreFailure.invalidTicket
            }

            try await store.commitRecord(staged, namespace: namespace)
            try await store.releaseMigration(namespace)
        }
    }

    public func cancelMigration(
        _ ticket: StateMigrationTicket,
        owner   : StateOwner
    ) async throws {
        try await perform(owner, allocatingMemory: false) { store, namespace in
            guard namespace.migration?.ticket == ticket else {
                throw StateStoreFailure.invalidTicket
            }

            let hasStage = namespace.migration?.stagedTicket != nil
            try await store.releaseMigration(namespace)
            if hasStage { try await store.discardStage(namespace) }
        }
    }

    /// close shuts the store down and leaves prepared files for bounded recovery at the next open.
    /// No new work may be admitted between shutdown and reconciliation. Always call this before
    /// releasing the host-owned store.
    public func close() async throws {
        guard !busy else { throw StateStoreFailure.busy }
        guard rootFD >= 0 else { return }

        busy = true
        defer { busy = false }

        for namespace in namespaces {
            try await releaseMigration(namespace)
            try await releaseStageRetention(namespace)
            for charge in [namespace.stateCharge, namespace.stageCharge].compactMap({ $0 }) {
                try await governor.release(charge.id, owner: charge.owner)
            }
        }
        for charge in baseCharges { try await governor.release(charge.id, owner: charge.owner) }
        if let charge = tableCharge { try await governor.release(charge.id, owner: charge.owner) }

        baseCharges.removeAll()
        tableCharge = nil
        namespaces.removeAll()
        diskBytes = 0
        Darwin.close(rootFD)
        rootFD = -1
    }

    private func available() throws {
        guard rootFD >= 0 else { throw StateStoreFailure.closed }
        guard !busy else { throw StateStoreFailure.busy }
    }

    private func perform<T: Sendable>(
        _ owner         : StateOwner,
        allocatingMemory: Bool = true,
        body            : (isolated AddonStateStore, Namespace) async throws -> T
    ) async throws -> T {
        try available()
        guard let namespace = namespaces.first(where: { $0.handle == owner }) else {
            throw StateStoreFailure.invalidOwner
        }
        try Task.checkCancellation()

        busy = true
        defer { busy = false }

        // Cleanup never reads payloads and must remain possible when the shared budget is full.
        let charge: ResourceReservation?
        if allocatingMemory {
            charge = try await governor.admit(
                .temporaryMemory(bytes: Self.operationBytes),
                owner: namespace.identity.addonID
            )
        } else {
            charge = nil
        }

        do {
            try Task.checkCancellation()
            let result = try await body(self, namespace)
            if let charge { try await governor.release(charge.id, owner: charge.owner) }
            return result
        } catch {
            if let charge { try await governor.release(charge.id, owner: charge.owner) }
            throw error
        }
    }

    private func reconcile(_ registrations: [StateRegistration]) async throws {
        let owner = registrations[0].identity.addonID
        // Only bounded namespace/identity metadata is eager; checkpoint snapshots are admitted on demand.
        let namespaceBytes = 2_048
        tableCharge = try await governor.admit(
            .state(bytes: registrations.count * namespaceBytes),
            owner: owner
        )
        namespaces = registrations.map(Namespace.init)
        for namespace in namespaces {
            let charge = try await reserveDisk(Self.metadataBytes, owner: namespace.identity.addonID)
            baseCharges.append(charge)
        }

        let scanCharge = try await governor.admit(
            .temporaryMemory(bytes: Self.operationBytes),
            owner: owner
        )
        do {
            let names = try directoryEntries()
            for name in names {
                try Task.checkCancellation()
                guard let namespace = namespaces.first(where: {
                    name == $0.name + ".state" || name == $0.name + ".stage"
                })
                else {
                    throw StateStoreFailure.unrecognizedEntry
                }

                let descriptor = try openFile(name)
                let count: Int
                do {
                    count = try checkedSize(descriptor) + Self.metadataBytes
                } catch {
                    Darwin.close(descriptor)
                    throw error
                }
                Darwin.close(descriptor)

                let charge = try await reserveDisk(count, owner: namespace.identity.addonID)
                if name.hasSuffix(".state") {
                    namespace.stateCharge = charge
                    namespace.stateBytes  = count
                } else {
                    namespace.stageCharge = charge
                    namespace.stageBytes  = count
                }
            }

            // No artifact is removed until the entire bounded inventory has been admitted.
            try Task.checkCancellation()
            for namespace in namespaces { try await discardStage(namespace) }
            try await governor.release(scanCharge.id, owner: scanCharge.owner)
        } catch {
            try await governor.release(scanCharge.id, owner: scanCharge.owner)
            throw error
        }
    }

    private func reserveDisk(
        _ count: Int,
        owner  : AddonID
    ) async throws -> ResourceReservation {
        guard count <= diskBudget - diskBytes else { throw StateStoreFailure.quotaExceeded }

        let reservation = try await governor.admit(.diskState(bytes: count), owner: owner)
        diskBytes += count

        return reservation
    }

    private func stageRecord(
        _ data   : Data,
        schema   : UInt32,
        namespace: Namespace
    ) async throws -> StateWriteTicket {
        guard data.count <= Self.maximumCheckpointBytes else { throw StateStoreFailure.oversized }
        guard schema > 0, schema <= namespace.maximumSchemaVersion else {
            throw StateStoreFailure.invalidConfiguration
        }
        guard namespace.staged == nil, namespace.stageCharge == nil else { throw StateStoreFailure.busy }

        let previous = try readRecord(namespace, staged: false)
        guard previous?.revision != UInt64.max else { throw StateStoreFailure.corrupt }

        let revision      = (previous?.revision ?? 0) + 1
        let count         = data.count + Self.headerBytes + Self.metadataBytes
        let retainedBytes = data.count + 128 + (previous.map { $0.data.count + 128 } ?? 0)
        let retention     = try await governor.admit(
            .state(bytes: retainedBytes),
            owner: namespace.identity.addonID
        )

        var charge : ResourceReservation?
        let name    = namespace.name + ".stage"
        var created = false
        do {
            try Task.checkCancellation()
            charge = try await reserveDisk(count, owner: namespace.identity.addonID)
            try Task.checkCancellation()

            let bytes = Self.encode(
                data,
                schema   : schema,
                revision : revision,
                namespace: namespace.name
            )
            let descriptor = openat(rootFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
            guard descriptor >= 0 else { throw StateStoreFailure.io(errno) }

            created = true
            do {
                _ = try checkedSize(descriptor)
                try bytes.withUnsafeBytes { buffer in
                    var written = 0
                    while written < buffer.count {
                        let count = Darwin.write(
                            descriptor,
                            buffer.baseAddress!.advanced(by: written),
                            buffer.count - written
                        )
                        if count < 0 && errno == EINTR { continue }
                        guard count > 0 else { throw StateStoreFailure.io(errno) }

                        written += count
                    }
                }
                guard fsync(descriptor) == 0 else { throw StateStoreFailure.io(errno) }

                Darwin.close(descriptor)
            } catch {
                Darwin.close(descriptor)
                throw error
            }
            try Task.checkCancellation()

            let candidate = try decode(bytes, namespace: namespace)
            let ticket    = StateWriteTicket(id: UUID())

            namespace.stageCharge    = charge
            namespace.stageBytes     = count
            namespace.stageRetention = retention
            namespace.staged         = Staged(
                ticket   : ticket,
                previous : previous,
                candidate: candidate
            )

            return ticket
        } catch {
            // If unlink fails, retain only the disk reservation and require explicit retry/shutdown.
            if let charge {
                if created && unlinkat(rootFD, name, 0) != 0 {
                    namespace.stageCharge = charge
                    namespace.stageBytes  = count
                } else {
                    diskBytes -= count
                    try await governor.release(charge.id, owner: charge.owner)
                }
            }
            try await governor.release(retention.id, owner: retention.owner)
            throw error
        }
    }

    private func commitRecord(
        _ ticket : StateWriteTicket,
        namespace: Namespace
    ) async throws {
        guard let staged = namespace.staged, staged.ticket == ticket else {
            throw StateStoreFailure.invalidTicket
        }
        guard try readRecord(namespace, staged: false) == staged.previous else {
            throw StateStoreFailure.staleRevision
        }
        guard try readRecord(namespace, staged: true) == staged.candidate else {
            throw StateStoreFailure.corrupt
        }
        try Task.checkCancellation()
        guard renameat(rootFD, namespace.name + ".stage", rootFD, namespace.name + ".state") == 0 else {
            throw StateStoreFailure.io(errno)
        }

        // Rename is the visibility commit point. No throwing/cancellation work may undo the new state afterward.
        let oldCharge = namespace.stateCharge
        diskBytes -= namespace.stateBytes
        namespace.stateCharge = namespace.stageCharge
        namespace.stateBytes  = namespace.stageBytes
        namespace.stageCharge = nil
        namespace.stageBytes  = 0
        try await releaseStageRetention(namespace)
        if let oldCharge { try await governor.release(oldCharge.id, owner: oldCharge.owner) }
    }

    private func discardStage(_ namespace: Namespace) async throws {
        try await releaseStageRetention(namespace)
        guard let charge = namespace.stageCharge else { return }

        try removeFile(namespace.name + ".stage")
        try await governor.release(charge.id, owner: charge.owner)
        diskBytes -= namespace.stageBytes
        namespace.stageCharge = nil
        namespace.stageBytes  = 0
        namespace.staged      = nil
    }

    private func releaseStageRetention(_ namespace: Namespace) async throws {
        let charge               = namespace.stageRetention
        namespace.staged         = nil
        namespace.stageRetention = nil
        if let charge { try await governor.release(charge.id, owner: charge.owner) }
    }

    private func releaseMigration(_ namespace: Namespace) async throws {
        let charge                   = namespace.migrationRetention
        namespace.migration          = nil
        namespace.migrationRetention = nil
        if let charge { try await governor.release(charge.id, owner: charge.owner) }
    }

    private func readRecord(
        _ namespace: Namespace,
        staged     : Bool
    ) throws -> StateCheckpoint? {
        let name       = namespace.name + (staged ? ".stage" : ".state")
        let descriptor = openat(rootFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if descriptor < 0 && errno == ENOENT {
            guard (staged ? namespace.stageCharge : namespace.stateCharge) == nil else {
                throw StateStoreFailure.corrupt
            }

            return nil
        }
        guard descriptor >= 0 else { throw StateStoreFailure.unsafePath }
        defer { Darwin.close(descriptor) }

        let size         = try checkedSize(descriptor)
        let chargedBytes = staged ? namespace.stageBytes : namespace.stateBytes
        guard chargedBytes == size + Self.metadataBytes else { throw StateStoreFailure.corrupt }

        var data = Data(count: size)
        try data.withUnsafeMutableBytes { buffer in
            var received = 0
            while received < size {
                let count = Darwin.read(descriptor, buffer.baseAddress!.advanced(by: received), size - received)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw StateStoreFailure.corrupt }

                received += count
            }
        }
        guard try checkedSize(descriptor) == size else { throw StateStoreFailure.corrupt }

        return try decode(data, namespace: namespace)
    }

    private static func encode(
        _ payload: Data,
        schema   : UInt32,
        revision : UInt64,
        namespace: String
    ) -> Data {
        var header = Data("CASCST01".utf8)
        func append(
            _ value: UInt64,
            count  : Int
        ) {
            for shift in (0..<count).reversed() { header.append(UInt8(truncatingIfNeeded: value >> (8 * shift))) }
        }

        append(UInt64(schema), count: 4)
        append(UInt64(payload.count), count: 4)
        append(revision, count: 8)

        var digest = SHA256()
        digest.update(data: Data(namespace.utf8))
        digest.update(data: header)
        digest.update(data: payload)
        header.append(contentsOf: digest.finalize())
        header.append(Data(repeating: 0, count: 8))
        header.append(payload)

        return header
    }

    private func decode(
        _ bytes  : Data,
        namespace: Namespace
    ) throws -> StateCheckpoint {
        guard bytes.count >= Self.headerBytes, bytes.prefix(8) == Data("CASCST01".utf8) else {
            throw StateStoreFailure.corrupt
        }

        func integer(_ range: Range<Int>) -> UInt64 {
            range.reduce(UInt64(0)) { ($0 << 8) | UInt64(bytes[$1]) }
        }

        let schema   = UInt32(integer(8..<12))
        let count    = integer(12..<16)
        let revision = integer(16..<24)
        guard schema > 0,
              revision > 0,
              count <= Self.maximumCheckpointBytes,
              count == bytes.count - Self.headerBytes,
              bytes[56..<64].allSatisfy({ $0 == 0 })
        else {
            throw StateStoreFailure.corrupt
        }

        var digest = SHA256()
        digest.update(data: Data(namespace.name.utf8))
        digest.update(data: bytes.prefix(24))
        digest.update(data: bytes.suffix(Int(count)))
        let checksum = Data(digest.finalize())
        guard checksum == bytes[24..<56] else { throw StateStoreFailure.corrupt }
        guard schema <= namespace.maximumSchemaVersion else { throw StateStoreFailure.futureSchema(schema) }

        return StateCheckpoint(
            data         : Data(bytes.suffix(Int(count))),
            schemaVersion: schema,
            revision     : revision,
            digest       : checksum
        )
    }

    private static func openRoot(_ root: URL) throws -> Int32 {
        let path       = root.path
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard root.isFileURL,
              path.hasPrefix("/"),
              !path.utf8.contains(0),
              !components.isEmpty,
              !components.contains(".."),
              !components.contains(".")
        else { throw StateStoreFailure.unsafePath }

        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { throw StateStoreFailure.unsafePath }

        do {
            for component in components {
                let next = openat(descriptor, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
                guard next >= 0 else { throw StateStoreFailure.unsafePath }

                Darwin.close(descriptor)
                descriptor = next
            }

            var info = stat()
            guard fstat(descriptor, &info) == 0,
                  info.st_uid == getuid(),
                  info.st_mode & 0o077 == 0
            else {
                throw StateStoreFailure.unsafePath
            }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else { throw StateStoreFailure.busy }

            return descriptor
        } catch {
            Darwin.close(descriptor)
            throw error
        }
    }

    private func openFile(_ name: String) throws -> Int32 {
        let descriptor = openat(rootFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard descriptor >= 0 else { throw StateStoreFailure.unsafePath }

        return descriptor
    }

    private func checkedSize(_ descriptor: Int32) throws -> Int {
        var info = stat()
        guard fstat(descriptor, &info) == 0,
              info.st_mode & S_IFMT == S_IFREG,
              info.st_nlink == 1,
              info.st_uid == getuid(),
              info.st_mode & 0o077 == 0
        else { throw StateStoreFailure.unsafePath }
        guard info.st_size >= 0, info.st_size <= Self.maximumCheckpointBytes + Self.headerBytes else {
            throw StateStoreFailure.oversized
        }

        return Int(info.st_size)
    }

    private func removeFile(_ name: String) throws {
        let descriptor = openat(rootFD, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if descriptor < 0 && errno == ENOENT { return }
        guard descriptor >= 0 else { throw StateStoreFailure.unsafePath }

        do {
            _ = try checkedSize(descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }
        Darwin.close(descriptor)
        guard unlinkat(rootFD, name, 0) == 0 else { throw StateStoreFailure.io(errno) }
    }

    private func directoryEntries() throws -> [String] {
        let duplicate = dup(rootFD)
        guard duplicate >= 0 else { throw StateStoreFailure.io(errno) }
        guard let directory = fdopendir(duplicate) else {
            Darwin.close(duplicate)
            throw StateStoreFailure.io(errno)
        }
        defer { closedir(directory) }

        var names: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) {
                    String(cString: $0)
                }
            }
            if name == "." || name == ".." { continue }
            guard names.count < namespaces.count * 2, name.utf8.count <= 70 else {
                throw StateStoreFailure.unrecognizedEntry
            }

            names.append(name)
            errno = 0
        }
        guard errno == 0 else { throw StateStoreFailure.io(errno) }

        return names
    }
}
