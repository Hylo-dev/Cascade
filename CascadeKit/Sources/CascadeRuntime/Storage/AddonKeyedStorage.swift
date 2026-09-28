//
//  AddonKeyedStorage.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation

/// AddonKeyedStorage owns independent bounded records and retained disk pools on a non-MainActor actor.
/// The host retains this ledger across close/reopen and revokes capabilities on session/permission loss.
/// Initial reconciliation failure requires a host-wide storage admission pause; this actor cannot pause
/// an independently trusted checkpoint store. No operation executes provider code or accepts its path.
/// Fixed metadata and scratch charges are logical admission bounds, not allocator-exact RSS/APFS claims.
actor AddonKeyedStorage {
    /// Pool keeps one canonical governor reservation and separate admitted/required scalar totals.
    private final class Pool {
        let storageClass : KeyedStorageClass
        var reservation  : ResourceReservation?
        var charged      = 0
        var required     = 0

        init(_ storageClass: KeyedStorageClass) { self.storageClass = storageClass }
    }

    /// Namespace retains only bounded identity, capability and two pool rows, never a key inventory.
    private final class Namespace {
        let identity     : VerifiedAddonIdentity
        let digest       : Data
        let name         : String
        let data         = Pool(.data)
        let cache        = Pool(.cache)
        var owner        : KeyedStorageOwner?
        var hasDirectory = false
        var hasData      = false
        var hasCache     = false
        // Existence and quota are committed by mkdir; durability is confirmed separately by fsync.
        var requiresEntrySync = false

        init(_ identity: VerifiedAddonIdentity) {
            self.identity = identity
            digest = KeyedStorageRecord.namespaceDigest(identity)
            name = KeyedStorageRecord.hex(digest)
        }

        func pool(_ storageClass: KeyedStorageClass) -> Pool { storageClass == .data ? data : cache }
        func hasClass(_ storageClass: KeyedStorageClass) -> Bool { storageClass == .data ? hasData : hasCache }
    }

    /// Fingerprint binds a revision/checksum to the exact held-file identity observed during staging.
    private struct Fingerprint: Equatable {
        let identity : KeyedStorageDirectory.FileIdentity
        let revision : UInt64
        let checksum : Data
    }

    /// Operation owns the single active transaction and refunds until every governor await completes.
    private final class Operation {
        let namespace : Namespace
        let owner     : KeyedStorageOwner?
        var scratch   : ResourceReservation?
        var retention : ResourceReservation?

        init(
            _ namespace : Namespace,
            owner       : KeyedStorageOwner?
        ) {
            self.namespace = namespace
            self.owner = owner
        }
    }

    /// Prepared retains only bounded ticket/key/fingerprint metadata; payload bytes stay on disk.
    private struct Prepared {
        let ticket       : KeyedWriteTicket
        let namespace    : Namespace
        let owner        : KeyedStorageOwner
        let storageClass : KeyedStorageClass
        let key          : Data
        let previous     : Fingerprint?
        let candidate    : Fingerprint
        let retention    : ResourceReservation
    }

    /// Pending preserves the full admitted stage charge when an unlink cannot be confirmed.
    private struct Pending {
        let namespace    : Namespace
        let storageClass : KeyedStorageClass
        let charge       : Int
    }

    /// Inventory stores scalar reconciliation totals for one registered namespace.
    private struct Inventory {
        var data         = 0
        var cache        = 0
        var hasDirectory = false
        var hasData      = false
        var hasCache     = false
    }

    /// ScanState exists only during synchronous traversal, within the admitted namespace allowance.
    private final class ScanState {
        var inventory : [Inventory]
        var total     = 4_096
        var pending   : Pending?

        init(count: Int) {
            inventory = Array(
                repeating : Inventory(),
                count     : count
            )
            inventory[0].data = 4_096
        }
    }

    private var scanState            : ScanState?
    private var rootFD               : Int32
    private let rootDevice           : dev_t
    private let rootInode            : ino_t
    private let access               : any RuntimeResourceAccess
    private let files                : any KeyedStorageFileOperations
    private let diskBudget           : Int
    private let namespaces           : [Namespace]
    private var metadata             : [ResourceReservation] = []
    private var active               : Operation?
    private var prepared             : Prepared?
    private var pending              : Pending?
    private var shouldDiscardPending = false
    private var uncertainRecordName  : String?
    private var isClosing            = false
    private var isReady              = false
    private var needsReconciliation  = false
    private var rootRequiresEntrySync = false

    private init(
        descriptor    : Int32,
        registrations : [KeyedStorageRegistration],
        access        : any RuntimeResourceAccess,
        files         : any KeyedStorageFileOperations,
        diskBudget    : Int,
        metadata      : [ResourceReservation]
    ) throws {
        var info = stat()
        guard
            fstat(
                descriptor,
                &info
            ) == 0
        else { throw KeyedStorageFailure.unsafePath }
        rootFD = descriptor
        rootDevice = info.st_dev
        rootInode = info.st_ino
        self.access = access
        self.files = files
        self.diskBudget = min(
            100 * 1_024 * 1_024,
            max(
                0,
                diskBudget
            )
        )
        self.metadata = metadata
        namespaces = registrations.map { Namespace($0.identity) }
    }

    deinit {
        // Durable pools deliberately outlive descriptor ownership. Governor shutdown, not deinit,
        // is the only owner-wide accounting boundary; releasing here would make real files free.
        if rootFD >= 0 { Darwin.close(rootFD) }
    }

    /// open reconciles all files before any capability can escape. Governor is always injected.
    static func open(
        root           : URL,
        registrations  : [KeyedStorageRegistration],
        governor       : ResourceGovernor,
        diskBudget     : Int = 100 * 1_024 * 1_024,
        resourceAccess : (any RuntimeResourceAccess)? = nil,
        fileOperations : any KeyedStorageFileOperations = POSIXKeyedStorageFileOperations()
    ) async throws -> AddonKeyedStorage {
        try Task.checkCancellation()
        guard !registrations.isEmpty, registrations.count <= 256,
            registrations.allSatisfy({ (1...512).contains($0.identity.publisher.utf8.count) })
        else { throw KeyedStorageFailure.invalidConfiguration }
        let access : any RuntimeResourceAccess = resourceAccess ?? governor
        guard access.resourceGovernorTarget === governor else { throw KeyedStorageFailure.invalidConfiguration }
        let descriptor = try KeyedStorageDirectory.openRoot(root)
        let store      : AddonKeyedStorage
        var metadata   : [ResourceReservation] = []
        do {
            for (index, registration) in registrations.enumerated() {
                let bytes       = 2_048 + (index == 0 ? 8_192 : 0)
                let reservation = try await access.admit(
                    .state(bytes: bytes),
                    owner : registration.identity.addonID
                )
                metadata.append(reservation)
                try Task.checkCancellation()
            }
            guard
                Set(registrations.map { KeyedStorageRecord.namespaceDigest($0.identity) }).count
                    == registrations.count
            else { throw KeyedStorageFailure.invalidConfiguration }
            store = try AddonKeyedStorage(
                descriptor    : descriptor,
                registrations : registrations,
                access        : access,
                files         : fileOperations,
                diskBudget    : diskBudget,
                metadata      : metadata
            )
        } catch {
            for reservation in metadata {
                try? await access.release(
                    reservation.id,
                    owner : reservation.owner
                )
            }
            Darwin.close(descriptor)
            throw error
        }
        do {
            try await store.initialize()
            return store
        } catch {
            await store.failedInitialOpen()
            throw error
        }
    }

    /// owner issues/renews a host capability only after reconciliation and prior cleanup.
    func owner(for identity: VerifiedAddonIdentity) throws -> KeyedStorageOwner {
        try available()
        guard active == nil, prepared == nil else { throw KeyedStorageFailure.busy }
        let digest = KeyedStorageRecord.namespaceDigest(identity)
        guard let namespace = namespaces.first(where: { $0.digest == digest }) else {
            throw KeyedStorageFailure.invalidOwner
        }
        if let owner = namespace.owner { return owner }
        let owner = KeyedStorageOwner(id: UUID())
        namespace.owner = owner
        return owner
    }

    /// read reserves scratch before allocating record buffers; caller owns returned Data retention.
    func read(
        key          : String,
        owner        : KeyedStorageOwner,
        storageClass : KeyedStorageClass = .data
    ) async throws -> Data? {
        let keyBytes  = try KeyedStorageRecord.validatedKey(key)
        let operation = try begin(owner)
        do {
            try await reserveScratch(operation)
            let value = try readRecord(
                operation.namespace,
                key          : keyBytes,
                storageClass : storageClass
            )?
            .0.value
            try validate(operation)
            await finish(operation)
            try Task.checkCancellation()
            try available()
            guard operation.namespace.owner == owner else { throw KeyedStorageFailure.invalidOwner }
            let readName = 
                operation.namespace.name + storageClass.directoryName
                + KeyedStorageRecord.hex(KeyedStorageRecord.keyDigest(keyBytes))
            if uncertainRecordName == readName { uncertainRecordName = nil }
            return value
        } catch { await finish(operation); throw error }
    }

    /// write composes the same prepared stage/commit seams used by host interruption tests.
    func write(
        _ value      : Data,
        key          : String,
        owner        : KeyedStorageOwner,
        storageClass : KeyedStorageClass = .data
    ) async throws {
        let ticket = try await stage(
            value,
            key          : key,
            owner        : owner,
            storageClass : storageClass
        )
        try await commit(
            ticket,
            owner : owner
        )
    }

    /// stage keeps the previous record visible and charges its full coexistence with the new file.
    func stage(
        _ value      : Data,
        key          : String,
        owner        : KeyedStorageOwner,
        storageClass : KeyedStorageClass = .data
    ) async throws -> KeyedWriteTicket {
        let keyBytes = try KeyedStorageRecord.validatedKey(key)
        guard value.count <= 65_536 else { throw KeyedStorageFailure.oversized }
        guard prepared == nil, pending == nil else { throw KeyedStorageFailure.busy }
        guard !needsReconciliation, uncertainRecordName == nil else {
            throw KeyedStorageFailure.committedDurabilityUncertain
        }
        let operation = try begin(owner)
        do {
            try await reserveScratch(operation)
            let namespace = operation.namespace
            let previous  = try fingerprint(
                namespace,
                key          : keyBytes,
                storageClass : storageClass
            )
            guard previous?.revision != UInt64.max else { throw KeyedStorageFailure.staleRevision }
            let revision  = (previous?.revision ?? 0) + 1
            let size      = 128 + keyBytes.count + value.count
            let retention = try await access.admit(
                .state(bytes: size),
                owner : namespace.identity.addonID
            )
            operation.retention = retention
            try validate(operation)
            try await ensureDirectories(
                operation,
                storageClass : storageClass
            )
            let pool = namespace.pool(storageClass)
            try await resize(
                pool,
                namespace : namespace,
                to        : pool.required + size + 4_096
            )
            try validate(operation)
            var encoded = KeyedStorageRecord.encode(
                key          : keyBytes,
                value        : value,
                namespace    : namespace.digest,
                storageClass : storageClass,
                revision     : revision
            )
            let candidate = try withClass(
                namespace,
                storageClass : storageClass
            ) { directory in
                let descriptor = openat(
                    directory,
                    ".pending",
                    O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC,
                    0o600
                )
                guard descriptor >= 0 else { throw KeyedStorageFailure.io(errno) }
                defer { Darwin.close(descriptor) }
                // Book file existence immediately, even if a later short write or fsync fails.
                pending = Pending(
                    namespace    : namespace,
                    storageClass : storageClass,
                    charge       : size + 4_096
                )
                pool.required += size + 4_096
                try KeyedStorageDirectory.write(
                    descriptor,
                    bytes      : encoded,
                    operations : files
                )
                guard
                    lseek(
                        descriptor,
                        0,
                        SEEK_SET
                    ) == 0
                else { throw KeyedStorageFailure.io(errno) }
                let identity = try KeyedStorageDirectory.identity(
                    descriptor,
                    maximum : KeyedStorageRecord.maximumBytes
                )
                let bytes = try KeyedStorageDirectory.read(
                    descriptor,
                    size : identity.size
                )
                let record = try KeyedStorageRecord.decode(
                    bytes,
                    key          : keyBytes,
                    namespace    : namespace.digest,
                    storageClass : storageClass
                )
                return Fingerprint(
                    identity : identity,
                    revision : record.revision,
                    checksum : record.checksum
                )
            }
            encoded = Data()
            try validate(operation)
            let ticket = KeyedWriteTicket(id: UUID())
            prepared = Prepared(
                ticket       : ticket,
                namespace    : namespace,
                owner        : owner,
                storageClass : storageClass,
                key          : keyBytes,
                previous     : previous,
                candidate    : candidate,
                retention    : retention
            )
            operation.retention = nil
            await finish(operation)
            // finish releases scratch through a governor await; cancellation or revoke/close wins.
            try Task.checkCancellation()
            guard namespace.owner == owner, !isClosing, prepared?.ticket == ticket else {
                throw KeyedStorageFailure.invalidOwner
            }
            return ticket
        } catch {
            // The final release may have completed before cancellation was observed. Reclaim the
            // operation row before asynchronous refunds so a new caller cannot overtake cleanup.
            if active == nil { active = operation }
            let cleanupFailed = await discardPending()
            await finish(operation)
            if cleanupFailed { throw KeyedStorageFailure.cleanupRequired }
            throw error
        }
    }

    /// commit performs final authority validation, rename and canonical bookkeeping without suspension.
    func commit(
        _ ticket : KeyedWriteTicket,
        owner    : KeyedStorageOwner
    ) async throws {
        guard prepared?.ticket == ticket, prepared?.owner == owner else {
            throw KeyedStorageFailure.invalidTicket
        }
        let operation = try begin(owner)
        do {
            guard let candidate = prepared, candidate.ticket == ticket, candidate.owner == owner else {
                throw KeyedStorageFailure.invalidTicket
            }
            try await reserveScratch(operation)
            let namespace = candidate.namespace
            guard
                try fingerprint(
                    namespace,
                    key          : candidate.key,
                    storageClass : candidate.storageClass
                )
                    == candidate.previous
            else { throw KeyedStorageFailure.staleRevision }
            let staged = try fingerprint(
                namespace,
                key          : candidate.key,
                storageClass : candidate.storageClass,
                name         : ".pending"
            )
            guard staged == candidate.candidate else { throw KeyedStorageFailure.staleRevision }
            var uncertain = false
            try withClass(
                namespace,
                storageClass : candidate.storageClass
            ) { directory in
                try validate(operation)
                guard prepared?.ticket == ticket else { throw KeyedStorageFailure.invalidTicket }
                let name = KeyedStorageRecord.hex(KeyedStorageRecord.keyDigest(candidate.key)) + ".value"
                guard
                    renameat(
                        directory,
                        ".pending",
                        directory,
                        name
                    ) == 0
                else {
                    throw KeyedStorageFailure.io(errno)
                }
                // Rename is visibility. No cancellation or revoke can interleave before this bookkeeping.
                let oldCharge = candidate.previous.map { $0.identity.size + 4_096 } ?? 0
                namespace.pool(candidate.storageClass).required -= oldCharge
                pending = nil
                prepared = nil
                operation.retention = candidate.retention
                uncertain = files.syncDirectory(directory) != 0
                if uncertain {
                    uncertainRecordName =
                        namespace.name + candidate.storageClass.directoryName
                        + KeyedStorageRecord.hex(KeyedStorageRecord.keyDigest(candidate.key))
                }
            }
            await finish(operation)
            if uncertain { throw KeyedStorageFailure.committedDurabilityUncertain }
        } catch {
            let cleanupFailed = await discardPending()
            await finish(operation)
            if cleanupFailed { throw KeyedStorageFailure.cleanupRequired }
            throw error
        }
    }

    /// cancel removes only the prepared file. A failed unlink retains its full pool charge.
    func cancel(
        _ ticket : KeyedWriteTicket,
        owner    : KeyedStorageOwner
    ) async throws {
        let operation = try begin(owner)
        guard prepared?.ticket == ticket, prepared?.owner == owner else {
            await finish(operation)
            throw KeyedStorageFailure.invalidTicket
        }
        let failed = await discardPending()
        await finish(operation)
        if failed { throw KeyedStorageFailure.cleanupRequired }
    }

    /// revoke invalidates canonical authority immediately, even while real admission is suspended.
    func revoke(owner: KeyedStorageOwner) async throws {
        guard let namespace = namespaces.first(where: { $0.owner == owner }) else {
            throw KeyedStorageFailure.invalidOwner
        }
        namespace.owner = nil
        if pending?.namespace === namespace { shouldDiscardPending = true }
        guard active == nil else { return }
        let operation = Operation(
            namespace,
            owner : nil
        )
        active = operation
        let failed = pending?.namespace === namespace ? await discardPending() : false
        await finish(operation)
        if failed { throw KeyedStorageFailure.cleanupRequired }
    }

    /// remove deletes one safely identified live key, including corrupt/future-format regular records.
    func remove(
        key          : String,
        owner        : KeyedStorageOwner,
        storageClass : KeyedStorageClass = .data
    ) async throws {
        let keyBytes = try KeyedStorageRecord.validatedKey(key)
        guard prepared == nil, pending == nil else { throw KeyedStorageFailure.busy }
        let operation = try begin(owner)
        do {
            try validate(operation)
            if operation.namespace.hasClass(storageClass) {
                try withClass(
                    operation.namespace,
                    storageClass : storageClass
                ) { directory in
                    let name = KeyedStorageRecord.hex(KeyedStorageRecord.keyDigest(keyBytes)) + ".value"
                    try removeFile(
                        directory,
                        name         : name,
                        namespace    : operation.namespace,
                        storageClass : storageClass
                    )
                }
            }
            await finish(operation)
        } catch { await finish(operation); throw error }
    }

    /// purgeCache is host-only and affects neither keyed data nor checkpoint storage.
    func purgeCache(identity: VerifiedAddonIdentity) async throws {
        try await removeIdentityFiles(
            identity,
            classes  : [.cache],
            revoking : false
        )
    }

    /// removeUserData explicitly revokes then streams deletion of this identity's keyed data and cache.
    func removeUserData(identity: VerifiedAddonIdentity) async throws {
        try await removeIdentityFiles(
            identity,
            classes  : KeyedStorageClass.allCases,
            revoking : true
        )
    }

    /// close closes admission immediately and returns draining instead of retaining async waiters.
    /// Durable disk and small ledger reservations remain until host governor shutdown or explicit deletion.
    func close() async throws -> KeyedStorageCloseStatus {
        isClosing = true
        isReady = false
        for namespace in namespaces { namespace.owner = nil }
        guard active == nil else { return .draining }
        guard rootFD >= 0 else { return .closed }
        guard let namespace = namespaces.first else { throw KeyedStorageFailure.invalidConfiguration }
        let operation = Operation(
            namespace,
            owner : nil
        )
        active = operation
        let failed = await discardPending()
        await finish(operation)
        if failed { throw KeyedStorageFailure.cleanupRequired }
        return .closed
    }

    /// reopen reconciles the same root into retained pools without doubling or releasing durable usage.
    func reopen(root: URL) async throws {
        guard rootFD < 0, active == nil else { throw KeyedStorageFailure.busy }
        let descriptor = try KeyedStorageDirectory.openRoot(root)
        var info       = stat()
        guard
            fstat(
                descriptor,
                &info
            ) == 0, info.st_dev == rootDevice, info.st_ino == rootInode
        else {
            Darwin.close(descriptor)
            throw KeyedStorageFailure.unsafePath
        }
        rootFD = descriptor
        isClosing = false
        guard let namespace = namespaces.first else { throw KeyedStorageFailure.invalidConfiguration }
        let operation = Operation(
            namespace,
            owner : nil
        )
        active = operation
        do {
            try await reconcile()
            try Task.checkCancellation()
            guard !isClosing else { throw KeyedStorageFailure.closed }
            isReady = true
            needsReconciliation = false
            uncertainRecordName = nil
            active = nil
        } catch {
            isClosing = true
            active = nil
            Darwin.close(rootFD)
            rootFD = -1
            throw error
        }
    }

    // MARK: - Operation ownership and accounting

    /// available refuses publication before reconciliation and immediately after close begins.
    private func available() throws {
        guard rootFD >= 0, isReady, !isClosing else { throw KeyedStorageFailure.closed }
    }

    /// begin claims the already-admitted operation row without queuing caller payloads.
    private func begin(_ owner: KeyedStorageOwner) throws -> Operation {
        try available()
        guard active == nil else { throw KeyedStorageFailure.busy }
        guard let namespace = namespaces.first(where: { $0.owner == owner }) else {
            throw KeyedStorageFailure.invalidOwner
        }
        let operation = Operation(
            namespace,
            owner : owner
        )
        active = operation
        return operation
    }

    /// validate checks canonical epoch and cancellation after actual admission suspension points.
    private func validate(_ operation: Operation) throws {
        try Task.checkCancellation()
        guard !isClosing, rootFD >= 0 else { throw KeyedStorageFailure.closed }
        guard active === operation, operation.owner == operation.namespace.owner,
            operation.owner != nil
        else { throw KeyedStorageFailure.invalidOwner }
    }

    /// reserveScratch records the real reservation before checking whether authority survived its await.
    private func reserveScratch(_ operation: Operation) async throws {
        let charge = try await access.admit(
            .temporaryMemory(bytes: KeyedStorageRecord.scratchBytes),
            owner : operation.namespace.identity.addonID
        )
        operation.scratch = charge
        try validate(operation)
    }

    /// resize records a successful governor mutation before another suspension or authority check.
    private func resize(
        _ pool    : Pool,
        namespace : Namespace,
        to bytes: Int
    ) async throws {
        if bytes == pool.charged { return }
        let total = namespaces.reduce(0) { $0 + $1.data.charged + $1.cache.charged }
        guard bytes <= diskBudget - (total - pool.charged) else { throw KeyedStorageFailure.quotaExceeded }
        if let reservation = pool.reservation, bytes == 0 {
            try await access.release(
                reservation.id,
                owner : reservation.owner
            )
            pool.reservation = nil
            pool.charged = 0
        } else if let reservation = pool.reservation {
            guard
                try await access.resizeDiskReservation(
                    reservation.id,
                    owner     : reservation.owner,
                    fromBytes : pool.charged,
                    toBytes   : bytes
                )
            else { throw KeyedStorageFailure.staleRevision }
            pool.charged = bytes
        } else if bytes > 0 {
            let request : ResourceRequest =
                pool.storageClass == .data ? .diskState(bytes: bytes) : .diskCache(bytes: bytes)
            let reservation = try await access.admit(
                request,
                owner : namespace.identity.addonID
            )
            pool.reservation = reservation
            pool.charged = bytes
        }
    }

    /// finish owns cleanup until the final governor return; no new operation can steal a pool transition.
    private func finish(_ operation: Operation) async {
        guard active === operation else { return }
        if shouldDiscardPending || isClosing || (operation.owner != nil && operation.namespace.owner != operation.owner)
        {
            if shouldDiscardPending || isClosing || pending?.namespace === operation.namespace {
                _ = await discardPending()
            }
        }
        if let retention = operation.retention {
            operation.retention = nil
            try? await access.release(
                retention.id,
                owner : retention.owner
            )
        }
        if let scratch = operation.scratch {
            operation.scratch = nil
            try? await access.release(
                scratch.id,
                owner : scratch.owner
            )
        }
        for namespace in namespaces {
            for pool in [namespace.data, namespace.cache] where pool.charged > pool.required {
                // A refusal is conservative: retain excess charge and require reconciliation.
                do {
                    try await resize(
                        pool,
                        namespace : namespace,
                        to        : pool.required
                    )
                } catch {
                    needsReconciliation = true
                }
            }
        }
        // Revoke/close may have arrived during a cleanup await after the first check.
        if shouldDiscardPending || isClosing || (operation.owner != nil && operation.namespace.owner != operation.owner)
        {
            if shouldDiscardPending || isClosing || pending?.namespace === operation.namespace {
                _ = await discardPending()
            }
            for namespace in namespaces {
                for pool in [namespace.data, namespace.cache] where pool.charged > pool.required {
                    do {
                        try await resize(
                            pool,
                            namespace : namespace,
                            to        : pool.required
                        )
                    } catch {
                        needsReconciliation = true
                    }
                }
            }
        }
        active = nil
        if isClosing, rootFD >= 0 {
            Darwin.close(rootFD)
            rootFD = -1
        }
    }

    /// discardPending drops sensitive state even when disk cleanup fails, retaining the orphan charge.
    private func discardPending() async -> Bool {
        let retention = prepared?.retention
        prepared = nil
        shouldDiscardPending = false
        var failed = false
        if let pending {
            do {
                try withClass(
                    pending.namespace,
                    storageClass : pending.storageClass
                ) { directory in
                    if let (
                        descriptor,
                        _
                    ) = try KeyedStorageDirectory.file(
                        directory,
                        name    : ".pending",
                        maximum : pending.storageClass.maximumBytes
                    ) {
                        Darwin.close(descriptor)
                        guard
                            files.unlink(
                                directory,
                                name : ".pending"
                            ) == 0
                        else {
                            throw KeyedStorageFailure.cleanupRequired
                        }
                    }
                    // Keep the full pending charge until directory-entry cleanup is confirmed.
                    // A retry may observe an already absent file and still must complete this fsync.
                    guard files.syncDirectory(directory) == 0 else { throw KeyedStorageFailure.cleanupRequired }
                    self.pending = nil
                    pending.namespace.pool(pending.storageClass).required -= pending.charge
                }
            } catch { failed = true; needsReconciliation = true }
        }
        if let retention {
            try? await access.release(
                retention.id,
                owner : retention.owner
            )
        }
        return failed
    }

    // MARK: - Held-directory operations

    /// ensureDirectories admits metadata before exclusive mkdir and persists each new parent entry.
    private func ensureDirectories(
        _ operation  : Operation,
        storageClass : KeyedStorageClass
    ) async throws {
        let namespace = operation.namespace
        if !namespace.hasDirectory {
            try await resize(
                namespace.data,
                namespace : namespace,
                to        : namespace.data.required + 4_096
            )
            try validate(operation)
            try KeyedStorageDirectory.createDirectory(
                rootFD,
                name : namespace.name
            )
            namespace.hasDirectory = true
            namespace.data.required += 4_096
            rootRequiresEntrySync = true
        }
        try synchronizeRootEntries()
        if !namespace.hasClass(storageClass) {
            let pool = namespace.pool(storageClass)
            try await resize(
                pool,
                namespace : namespace,
                to        : pool.required + 4_096
            )
            try validate(operation)
            guard
                let descriptor = try KeyedStorageDirectory.child(
                    rootFD,
                    name : namespace.name
                )
            else {
                throw KeyedStorageFailure.unsafePath
            }
            defer { Darwin.close(descriptor) }
            try KeyedStorageDirectory.createDirectory(
                descriptor,
                name : storageClass.directoryName
            )
            if storageClass == .data { namespace.hasData = true } else { namespace.hasCache = true }
            pool.required += 4_096
            namespace.requiresEntrySync = true
        }
        try synchronizeNamespaceEntries(namespace)
    }

    /// synchronizeRootEntries repairs unconfirmed managed namespace entries in the held root.
    /// The host-provided root's own unmanaged ancestors are outside this durability boundary.
    private func synchronizeRootEntries() throws {
        guard rootRequiresEntrySync else { return }
        try Task.checkCancellation()
        guard files.syncDirectory(rootFD) == 0 else { throw KeyedStorageFailure.io(errno) }
        rootRequiresEntrySync = false
    }

    /// synchronizeNamespaceEntries confirms data/cache directory entries without per-write ancestor churn.
    /// A failed sync retains the obligation; a missing namespace retains it until later recreation.
    private func synchronizeNamespaceEntries(_ namespace: Namespace) throws {
        guard namespace.requiresEntrySync, namespace.hasDirectory else { return }
        try Task.checkCancellation()
        guard
            let descriptor = try KeyedStorageDirectory.child(
                rootFD,
                name : namespace.name
            )
        else { throw KeyedStorageFailure.unsafePath }
        defer { Darwin.close(descriptor) }
        guard files.syncDirectory(descriptor) == 0 else { throw KeyedStorageFailure.io(errno) }
        namespace.requiresEntrySync = false
    }

    /// withClass borrows namespace/class descriptors for one synchronous operation and closes both.
    private func withClass<T>(
        _ namespace  : Namespace,
        storageClass : KeyedStorageClass,
        body         : (Int32) throws -> T
    ) throws -> T {
        guard
            let descriptor = try KeyedStorageDirectory.child(
                rootFD,
                name : namespace.name
            )
        else {
            throw KeyedStorageFailure.unsafePath
        }
        defer { Darwin.close(descriptor) }
        guard
            let directory = try KeyedStorageDirectory.child(
                descriptor,
                name : storageClass.directoryName
            )
        else {
            throw KeyedStorageFailure.unsafePath
        }
        defer { Darwin.close(directory) }
        return try body(directory)
    }

    /// readRecord validates file safety, exact key binding and checksum under previously admitted scratch.
    private func readRecord(
        _ namespace  : Namespace,
        key          : Data,
        storageClass : KeyedStorageClass,
        name         : String? = nil
    ) throws -> (KeyedStorageRecord, Fingerprint)? {
        guard namespace.hasClass(storageClass) else { return nil }
        return try withClass(
            namespace,
            storageClass : storageClass
        ) { directory in
            let filename = name ?? KeyedStorageRecord.hex(KeyedStorageRecord.keyDigest(key)) + ".value"
            guard
                let (
                    descriptor,
                    identity
                ) = try KeyedStorageDirectory.file(
                    directory,
                    name    : filename,
                    maximum : storageClass.maximumBytes
                )
            else { return nil }
            defer { Darwin.close(descriptor) }
            let bytes = try KeyedStorageDirectory.read(
                descriptor,
                size : identity.size
            )
            let record = try KeyedStorageRecord.decode(
                bytes,
                key          : key,
                namespace    : namespace.digest,
                storageClass : storageClass
            )
            return (
                record,
                Fingerprint(
                    identity : identity,
                    revision : record.revision,
                    checksum : record.checksum
                )
            )
        }
    }

    /// fingerprint drops the previous payload before candidate admission and retains only fixed metadata.
    private func fingerprint(
        _ namespace  : Namespace,
        key          : Data,
        storageClass : KeyedStorageClass,
        name         : String? = nil
    ) throws -> Fingerprint? {
        try readRecord(
            namespace,
            key          : key,
            storageClass : storageClass,
            name         : name
        )?
        .1
    }

    /// removeFile updates required bytes only after a safe regular file has actually been unlinked.
    private func removeFile(
        _ directory  : Int32,
        name         : String,
        namespace    : Namespace,
        storageClass : KeyedStorageClass
    ) throws {
        guard
            let (
                descriptor,
                identity
            ) = try KeyedStorageDirectory.file(
                directory,
                name    : name,
                maximum : storageClass.maximumBytes
            )
        else { return }
        Darwin.close(descriptor)
        guard
            files.unlink(
                directory,
                name : name
            ) == 0
        else { throw KeyedStorageFailure.cleanupRequired }
        namespace.pool(storageClass).required -= identity.size + 4_096
        if files.syncDirectory(directory) != 0 { throw KeyedStorageFailure.committedDurabilityUncertain }
    }

    /// removeIdentityFiles streams explicit host deletion; any error leaves surviving files charged.
    private func removeIdentityFiles(
        _ identity : VerifiedAddonIdentity,
        classes    : [KeyedStorageClass],
        revoking   : Bool
    ) async throws {
        try available()
        let digest = KeyedStorageRecord.namespaceDigest(identity)
        guard let namespace = namespaces.first(where: { $0.digest == digest }) else {
            throw KeyedStorageFailure.invalidOwner
        }
        if revoking {
            namespace.owner = nil
            if pending?.namespace === namespace { shouldDiscardPending = true }
        }
        guard active == nil else { throw KeyedStorageFailure.busy }
        let operation = Operation(
            namespace,
            owner : nil
        )
        active = operation
        do {
            if let pending, pending.namespace === namespace, classes.contains(pending.storageClass) {
                guard !(await discardPending()) else { throw KeyedStorageFailure.cleanupRequired }
            }
            try Task.checkCancellation()
            guard !isClosing, active === operation, rootFD >= 0 else { throw KeyedStorageFailure.closed }
            for storageClass in classes where namespace.hasClass(storageClass) {
                try withClass(
                    namespace,
                    storageClass : storageClass
                ) { directory in
                    try KeyedStorageDirectory.entries(
                        directory,
                        maximumCount     : storageClass.maximumBytes / 4_096,
                        maximumNameBytes : 70
                    ) { name in
                        guard KeyedStorageDirectory.isValueName(name) else {
                            throw KeyedStorageFailure.unrecognizedEntry
                        }
                        try removeFile(
                            directory,
                            name         : name,
                            namespace    : namespace,
                            storageClass : storageClass
                        )
                    }
                }
            }
            await finish(operation)
        } catch { await finish(operation); throw error }
    }

    // MARK: - Streaming reconciliation

    /// initialize runs only after registry and operation metadata have been admitted by the factory.
    private func initialize() async throws {
        try await reconcile()
        isReady = true
    }

    /// failedInitialOpen refunds an unpublished attempt; the host must keep storage admission paused.
    private func failedInitialOpen() async {
        for namespace in namespaces {
            for pool in [namespace.data, namespace.cache] {
                if let reservation = pool.reservation {
                    try? await access.release(
                        reservation.id,
                        owner : reservation.owner
                    )
                    pool.reservation = nil
                    pool.charged = 0
                }
            }
        }
        for reservation in metadata {
            try? await access.release(
                reservation.id,
                owner : reservation.owner
            )
        }
        metadata.removeAll()
        if rootFD >= 0 { Darwin.close(rootFD); rootFD = -1 }
        isClosing = true
    }

    /// reconcile retains only one current name and scalar namespace totals, never an inventory of keys.
    private func scanInventory() throws -> ([Inventory], Pending?) {
        scanState = ScanState(count: namespaces.count)
        defer { scanState = nil }
        guard 4_096 <= diskBudget else { throw KeyedStorageFailure.quotaExceeded }
        try KeyedStorageDirectory.entries(
            rootFD,
            maximumCount     : namespaces.count,
            maximumNameBytes : 64
        ) { name in
            guard let index = namespaces.firstIndex(where: { $0.name == name }) else {
                throw KeyedStorageFailure.unrecognizedEntry
            }
            let namespace = namespaces[index]
            guard
                let descriptor = try KeyedStorageDirectory.child(
                    rootFD,
                    name : name
                )
            else {
                throw KeyedStorageFailure.unsafePath
            }
            defer { Darwin.close(descriptor) }
            try scanAdd(
                4_096,
                index        : index,
                storageClass : .data
            )
            scanState?.inventory[index].hasDirectory = true
            try KeyedStorageDirectory.entries(
                descriptor,
                maximumCount     : 2,
                maximumNameBytes : 5
            ) { className in
                guard let storageClass = KeyedStorageClass.allCases.first(where: { $0.directoryName == className }),
                    let directory = try KeyedStorageDirectory.child(
                        descriptor,
                        name : className
                    )
                else {
                    throw KeyedStorageFailure.unrecognizedEntry
                }
                defer { Darwin.close(directory) }
                try scanAdd(
                    4_096,
                    index        : index,
                    storageClass : storageClass
                )
                if storageClass == .data {
                    scanState?.inventory[index].hasData = true
                } else {
                    scanState?.inventory[index].hasCache = true
                }
                try KeyedStorageDirectory.entries(
                    directory,
                    maximumCount : min(
                        diskBudget,
                        storageClass.maximumBytes
                    ) / 4_096,
                    maximumNameBytes : 70,
                    permitNext       : {
                        guard let scanState = self.scanState,
                            scanState.total <= self.diskBudget - 4_096
                        else {
                            throw KeyedStorageFailure.quotaExceeded
                        }
                        let current = 
                            storageClass == .data
                            ? scanState.inventory[index].data
                            : scanState.inventory[index].cache
                        guard current <= storageClass.maximumBytes - 4_096 else {
                            throw KeyedStorageFailure.quotaExceeded
                        }
                    }
                ) { filename in
                    guard let scanState, scanState.total <= diskBudget - 4_096 else {
                        throw KeyedStorageFailure.quotaExceeded
                    }
                    guard filename == ".pending" || KeyedStorageDirectory.isValueName(filename) else {
                        throw KeyedStorageFailure.unrecognizedEntry
                    }
                    guard
                        let (
                            file,
                            identity
                        ) = try KeyedStorageDirectory.file(
                            directory,
                            name    : filename,
                            maximum : storageClass.maximumBytes
                        )
                    else { throw KeyedStorageFailure.unsafePath }
                    Darwin.close(file)
                    let charge = identity.size + 4_096
                    try scanAdd(
                        charge,
                        index        : index,
                        storageClass : storageClass
                    )
                    if filename == ".pending" {
                        guard scanState.pending == nil else { throw KeyedStorageFailure.unrecognizedEntry }
                        scanState.pending = Pending(
                            namespace    : namespace,
                            storageClass : storageClass,
                            charge       : charge
                        )
                    }
                }
            }
        }
        guard let scanState else { throw KeyedStorageFailure.invalidConfiguration }
        return (scanState.inventory, scanState.pending)
    }

    /// scanAdd enforces logical metadata/file ceilings before advancing the streaming inventory.
    private func scanAdd(
        _ amount     : Int,
        index        : Int,
        storageClass : KeyedStorageClass
    ) throws {
        guard let scanState, amount <= diskBudget - scanState.total else {
            throw KeyedStorageFailure.quotaExceeded
        }
        let current = storageClass == .data ? scanState.inventory[index].data : scanState.inventory[index].cache
        guard amount <= storageClass.maximumBytes - current else { throw KeyedStorageFailure.quotaExceeded }
        scanState.total += amount
        if storageClass == .data {
            scanState.inventory[index].data += amount
        } else {
            scanState.inventory[index].cache += amount
        }
    }

    /// reconcile admits the complete inventory before cleanup and rolls back only this attempt on refusal.
    private func reconcile() async throws {
        let (
            inventory,
            recoveredPending
        ) = try scanInventory()
        let oldCharges = namespaces.map { ($0.data.charged, $0.cache.charged) }
        do {
            // Growth is admitted for the entire inventory before any recovery deletion or shrink.
            for (index, namespace) in namespaces.enumerated() {
                try await resize(
                    namespace.data,
                    namespace : namespace,
                    to        : max(
                        namespace.data.charged,
                        inventory[index].data
                    )
                )
                try Task.checkCancellation()
                guard !isClosing else { throw KeyedStorageFailure.closed }
                try await resize(
                    namespace.cache,
                    namespace : namespace,
                    to        : max(
                        namespace.cache.charged,
                        inventory[index].cache
                    )
                )
                try Task.checkCancellation()
                guard !isClosing else { throw KeyedStorageFailure.closed }
            }
        } catch {
            for (index, namespace) in namespaces.enumerated() {
                try? await resize(
                    namespace.data,
                    namespace : namespace,
                    to        : oldCharges[index].0
                )
                try? await resize(
                    namespace.cache,
                    namespace : namespace,
                    to        : oldCharges[index].1
                )
            }
            throw error
        }
        for (index, namespace) in namespaces.enumerated() {
            namespace.data.required = inventory[index].data
            namespace.cache.required = inventory[index].cache
            namespace.hasDirectory = inventory[index].hasDirectory
            namespace.hasData = inventory[index].hasData
            namespace.hasCache = inventory[index].hasCache
            namespace.owner = nil
            // A visible entry is not durable proof, including on a fresh process with no old flags.
            // Reconcile repairs discovered managed parents once before publishing capabilities.
            rootRequiresEntrySync = rootRequiresEntrySync || namespace.hasDirectory
            namespace.requiresEntrySync = namespace.requiresEntrySync || namespace.hasData || namespace.hasCache
        }
        try synchronizeRootEntries()
        for namespace in namespaces { try synchronizeNamespaceEntries(namespace) }
        pending = recoveredPending
        guard !(await discardPending()) else { throw KeyedStorageFailure.cleanupRequired }
        for namespace in namespaces {
            try await resize(
                namespace.data,
                namespace : namespace,
                to        : namespace.data.required
            )
            try Task.checkCancellation()
            guard !isClosing else { throw KeyedStorageFailure.closed }
            try await resize(
                namespace.cache,
                namespace : namespace,
                to        : namespace.cache.required
            )
            try Task.checkCancellation()
            guard !isClosing else { throw KeyedStorageFailure.closed }
        }
    }
}
