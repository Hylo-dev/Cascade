//
//  SwiftDataArchive.swift
//  Cascade
//

import CascadeContracts
import Darwin
import Foundation

/// SwiftDataArchive owns one verified owner's persistent framework archive and protected ledger.
/// make inventories existing files without opening SwiftData. The host can therefore discover
/// every retained owner before opening any framework store. Suspension retains the worker/lock;
/// deinitialization releases only the descriptor, never retained disk accounting.
actor SwiftDataArchive {
    nonisolated let identity              : VerifiedAddonIdentity
    nonisolated let resourceGovernorTarget: ResourceGovernor

    // Covers bounded parent/child URLs, the 64-byte namespace name and retained control state.
    private static let metadataBytes           = 16_384
    private static let frameworkWorkspaceBytes = 1_024 * 1_024
    private static let envelopeBytes           = 4_096
    // Read/open covers one maximum old row and one handoff; saves use the actual candidate.
    // These protected controlled buffers do not establish a ceiling on framework caches/RSS.
    private static let controlMemoryBytes = 65_536
    private static let readMemoryBytes    = 2 * SwiftDataArchiveGeneration.maximumPayloadBytes
        + controlMemoryBytes

    private let root             : URL
    // A negative child descriptor means never acquired; a held child is never discarded/adopted again.
    private var descriptor       : Int32
    private let parent           : Parent?
    private let directoryCreation: any SwiftDataArchiveDirectoryCreating
    private let token            : ObservedDiskToken
    private let observer         : any SwiftDataArchiveObserving
    private let commitCheck      : any SwiftDataArchiveCommitChecking
    private var worker           : SwiftDataArchiveWorker?
    private var active           : UUID?
    private var epoch                  = UUID()
    private var hasStarted             = false
    private var isSuspended            = false
    private var hasFault               = false
    private var permitsFrameworkAccess = false
    private var chargedBytes           = 0
    private var measuredBytes          = 0
    private var rawInventoryStatus: SwiftDataArchiveInventoryStatus = .unobserved

    /// Parent keeps the caller's already-locked open file description alive for discovery.
    private struct Parent: Sendable {
        let root      : URL
        let descriptor: Int32
        let name      : String
    }

    private init(
        identity         : VerifiedAddonIdentity,
        root             : URL,
        descriptor       : Int32,
        governor         : ResourceGovernor,
        token            : ObservedDiskToken,
        observer         : any SwiftDataArchiveObserving,
        commitCheck      : any SwiftDataArchiveCommitChecking,
        parent           : Parent? = nil,
        directoryCreation: any SwiftDataArchiveDirectoryCreating = NativeSwiftDataArchiveDirectoryCreation()
    ) {
        self.identity          = identity
        self.root              = root
        self.descriptor        = descriptor
        self.parent            = parent
        self.directoryCreation = directoryCreation
        resourceGovernorTarget = governor
        self.token             = token
        self.observer          = observer
        self.commitCheck       = commitCheck
    }

    deinit {
        if descriptor >= 0 { Darwin.close(descriptor) }
        if let parent { Darwin.close(parent.descriptor) }
    }

    /// make admits bounded lifetime metadata before retaining the owner/root and raw inventory.
    /// No framework work runs here. Once an object exists, failed inventory leaves it faulted
    /// with its ledger retained rather than throwing away newly discovered ownership.
    static func make(
        identity   : VerifiedAddonIdentity,
        root       : URL,
        governor   : ResourceGovernor,
        observer   : any SwiftDataArchiveObserving = NativeSwiftDataArchiveObserver(),
        commitCheck: any SwiftDataArchiveCommitChecking = NativeSwiftDataArchiveCommitCheck()
    ) async throws -> SwiftDataArchive {
        try SwiftDataArchiveDirectory.validateRootURL(root)
        guard !identity.publisher.isEmpty,
              identity.publisher.utf8.count <= 512 else {
            throw SwiftDataArchiveFailure.invalidConfiguration
        }
        let token = try await governor.admitObservedDisk(
            bytes                : 0,
            owner                : identity.addonID,
            retainedMetadataBytes: metadataBytes
        )
        let descriptor: Int32
        do {
            try Task.checkCancellation()
            descriptor = try KeyedStorageDirectory.openRoot(root)
        } catch {
            try await governor.completeObservedDisk(
                token,
                owner: identity.addonID
            )
            throw error
        }
        let archive = SwiftDataArchive(
            identity   : identity,
            root       : root,
            descriptor : descriptor,
            governor   : governor,
            token      : token,
            observer   : observer,
            commitCheck: commitCheck
        )
        await archive.establishInventory()
        return archive
    }

    /// discover retains a ledger and parent before inspecting a possibly absent owner directory.
    /// The caller holds parentDescriptor through duplication. No child or framework files are created.
    static func discover(
        identity         : VerifiedAddonIdentity,
        parentRoot       : URL,
        parentDescriptor : Int32,
        governor         : ResourceGovernor,
        observer         : any SwiftDataArchiveObserving = NativeSwiftDataArchiveObserver(),
        commitCheck      : any SwiftDataArchiveCommitChecking = NativeSwiftDataArchiveCommitCheck(),
        directoryCreation: any SwiftDataArchiveDirectoryCreating = NativeSwiftDataArchiveDirectoryCreation()
    ) async throws -> SwiftDataArchive {
        try SwiftDataArchiveDirectory.validateRootURL(parentRoot)
        guard !identity.publisher.isEmpty, identity.publisher.utf8.count <= 512 else {
            throw SwiftDataArchiveFailure.invalidConfiguration
        }
        let name = KeyedStorageRecord.hex(KeyedStorageRecord.namespaceDigest(identity))
        let root = parentRoot.appendingPathComponent(name)
        try SwiftDataArchiveDirectory.validateRootURL(root)
        try SwiftDataArchiveDirectory.validateHeldRoot(
            root      : parentRoot,
            descriptor: parentDescriptor
        )
        let token = try await governor.admitObservedDisk(
            bytes                : 0,
            owner                : identity.addonID,
            retainedMetadataBytes: metadataBytes
        )
        let duplicate: Int32
        do {
            try Task.checkCancellation()
            duplicate = try SwiftDataArchiveDirectory.duplicateParent(
                root      : parentRoot,
                descriptor: parentDescriptor
            )
        } catch {
            try await governor.completeObservedDisk(
                token,
                owner: identity.addonID
            )
            throw error
        }
        let archive = SwiftDataArchive(
            identity         : identity,
            root             : root,
            descriptor       : -1,
            governor         : governor,
            token            : token,
            observer         : observer,
            commitCheck      : commitCheck,
            parent           : Parent(
                root      : parentRoot,
                descriptor: duplicate,
                name      : name
            ),
            directoryCreation: directoryCreation
        )
        await archive.establishInventory()
        return archive
    }

    /// inventoryStatus reports the last reconciled raw observation independently of model validity.
    func inventoryStatus() -> SwiftDataArchiveInventoryStatus { rawInventoryStatus }

    /// establishInventory records preexisting debt without granting framework write authority.
    private func establishInventory() async {
        do { try await observe() }
        catch { hasFault = true }
    }

    /// status samples canonical owner/global debt; it grants no admission across suspension.
    func status() async -> SwiftDataArchiveStatus {
        do {
            let disk = try await resourceGovernorTarget.observedDiskStatus(
                token,
                owner: identity.addonID
            )
            let state: SwiftDataArchiveStatus.State
            if hasFault || (!permitsFrameworkAccess && rawInventoryStatus != .absent) { state = .faulted }
            else if isSuspended { state = .suspended }
            else if !disk.permitsWrites { state = .overbudget }
            else { state = hasStarted ? .ready : .unavailable }
            return SwiftDataArchiveStatus(
                state             : state,
                measuredBytes     : measuredBytes,
                ownerOverageBytes : disk.ownerOverageBytes,
                globalOverageBytes: disk.globalOverageBytes,
                isBusy            : active != nil
            )
        } catch {
            hasFault = true
            return SwiftDataArchiveStatus(
                state             : .faulted,
                measuredBytes     : measuredBytes,
                ownerOverageBytes : 0,
                globalOverageBytes: 0,
                isBusy            : active != nil
            )
        }
    }

    /// start opens only after strict workspace growth and reuses an existing worker on resume.
    func start() async throws -> SwiftDataArchiveStatus {
        let operation = try begin(requiresStarted: false)
        isSuspended   = false
        defer { finish(operation) }
        return try await resourceGovernorTarget.withAssetDecodeReservation(
            bytes: Self.readMemoryBytes,
            owner: identity.addonID
        ) {
            try await self.performStart(operation)
        }
    }

    /// performStart keeps any returned container owned before checking interrupted startup.
    private func performStart(_ operation: UUID) async throws -> SwiftDataArchiveStatus {
        do {
            try await ensureDirectory(operation)
            try validate(operation)
            if worker == nil {
                try await growDisk(by: Self.frameworkWorkspaceBytes + Self.envelopeBytes)
                try validate(operation)
                try SwiftDataArchiveDirectory.prepareStore(
                    root      : root,
                    descriptor: descriptor
                )
                let root = self.root
                // Await completion even after cancellation: a container may have created files.
                // Retain a returned worker before checking the epoch; no physical-close fiction.
                worker = try await Task.detached {
                    try SwiftDataArchiveWorker(root: root)
                }.value
                try validate(operation)
            }
            guard let worker else { throw SwiftDataArchiveFailure.unavailable }
            try await worker.validateArchive(identity: identity)
            try await observe()
            try validate(operation)
            hasStarted = true
            hasFault   = false
            return await status()
        } catch {
            let failure = error
            await observeAfterFailure(failure)
            throw failure
        }
    }

    /// save returns a known commit with its observed status even if cancellation or suspension
    /// arrived while SwiftData saved. Rejection before that commit throws and preserves old data.
    func save(
        _ generation              : SwiftDataArchiveGeneration,
        replacing expectedRevision: UInt64?
    ) async throws -> SwiftDataArchiveSaveOutcome {
        try generation.validate()
        let operation = try begin(requiresStarted: true)
        defer { finish(operation) }
        return try await resourceGovernorTarget.withAssetDecodeReservation(
            bytes: SwiftDataArchiveGeneration.maximumPayloadBytes
                + 2 * generation.payload.count + Self.controlMemoryBytes,
            owner: identity.addonID
        ) {
            try await self.performSave(
                generation,
                replacing: expectedRevision,
                operation: operation
            )
        }
    }

    /// performSave carries the known-commit bit through mandatory postoperation observation.
    private func performSave(
        _ generation              : SwiftDataArchiveGeneration,
        replacing expectedRevision: UInt64?,
        operation                 : UUID
    ) async throws -> SwiftDataArchiveSaveOutcome {
        var committed = false
        do {
            try await observe()
            try validate(operation)
            try await growDisk(
                by: generation.payload.count + Self.envelopeBytes + Self.frameworkWorkspaceBytes
            )
            try validate(operation)
            guard let worker else { throw SwiftDataArchiveFailure.unavailable }
            try SwiftDataArchiveDirectory.validateHeldRoot(
                root      : root,
                descriptor: descriptor
            )
            let accepted    = generation.ownedCopy()
            let root        = self.root
            let descriptor  = self.descriptor
            let commitCheck = self.commitCheck
            let parent = self.parent
            try await worker.save(
                accepted,
                replacing   : expectedRevision,
                identity    : identity,
                beforeCommit: {
                    if let parent {
                        try SwiftDataArchiveDirectory.validateHeldRoot(
                            root      : parent.root,
                            descriptor: parent.descriptor
                        )
                    }
                    try commitCheck.validateCommit(
                        root      : root,
                        descriptor: descriptor
                    )
                }
            )
            committed = true
            try await observe()
            return SwiftDataArchiveSaveOutcome(
                revision: generation.revision,
                status  : await status()
            )
        } catch {
            let failure = error
            await observeAfterFailure(failure)
            if committed {
                return SwiftDataArchiveSaveOutcome(
                    revision: generation.revision,
                    status  : await status()
                )
            }
            throw failure
        }
    }

    /// withGeneration keeps controlled payload memory protected through the entire host callback.
    /// The internal caller must not retain payload bytes beyond the callback or return them in
    /// Result; Sendable does not enforce this trusted no-escape contract. Fresh contexts release
    /// row ownership before handoff. Existing overbudget data remains readable without a save.
    func withGeneration<Result: Sendable>(
        operation: @Sendable (SwiftDataArchiveGeneration?) async throws -> Result
    ) async throws -> Result {
        let admission = try begin(requiresStarted: true)
        defer { finish(admission) }
        return try await resourceGovernorTarget.withAssetDecodeReservation(
            bytes: Self.readMemoryBytes,
            owner: identity.addonID
        ) {
            try await self.performRead(
                admission: admission,
                operation: operation
            )
        }
    }

    /// performRead reconciles framework effects before the protected host callback begins.
    private func performRead<Result: Sendable>(
        admission: UUID,
        operation: @Sendable (SwiftDataArchiveGeneration?) async throws -> Result
    ) async throws -> Result {
        let generation: SwiftDataArchiveGeneration?
        do {
            try await observe()
            try validate(admission)
            guard let worker else { throw SwiftDataArchiveFailure.unavailable }
            generation = try await worker.read(identity: identity)
            try await observe()
            try validate(admission)
        } catch {
            let failure = error
            await observeAfterFailure(failure)
            throw failure
        }
        // No framework work follows the callback. Its host effects cannot be declared rolled
        // back because suspension or cancellation arrived while its final result was returning.
        return try await operation(generation)
    }

    /// reconcile may recover logical availability only from a new complete safe inventory.
    func reconcile() async throws -> SwiftDataArchiveStatus {
        let operation = try begin(requiresStarted: false)
        defer { finish(operation) }
        try await observe()
        return await status()
    }

    /// suspend invalidates pending return authority immediately and retains physical ownership.
    func suspend() async -> SwiftDataArchiveStatus {
        isSuspended = true
        epoch       = UUID()
        return await status()
    }

    /// begin bounds actor reentrancy before the first await; competing inputs are not queued here.
    private func begin(requiresStarted: Bool) throws -> UUID {
        try Task.checkCancellation()
        guard active == nil else { throw SwiftDataArchiveFailure.busy }
        if requiresStarted {
            guard hasStarted, !isSuspended, !hasFault, permitsFrameworkAccess else {
                throw SwiftDataArchiveFailure.unavailable
            }
        }
        let operation = UUID()
        epoch         = operation
        active        = operation
        return operation
    }

    /// validate requires both current operation authority and the held directory identities.
    private func validate(_ operation: UUID) throws {
        try validateAuthority(operation)
        guard permitsFrameworkAccess, !hasFault, descriptor >= 0 else {
            throw SwiftDataArchiveFailure.unavailable
        }
        if let parent {
            try SwiftDataArchiveDirectory.validateHeldRoot(
                root      : parent.root,
                descriptor: parent.descriptor
            )
        }
        try SwiftDataArchiveDirectory.validateHeldRoot(
            root      : root,
            descriptor: descriptor
        )
    }

    /// validateAuthority permits an intentionally absent directory to reach strict provisioning.
    private func validateAuthority(_ operation: UUID) throws {
        try Task.checkCancellation()
        guard active == operation, epoch == operation, !isSuspended else {
            throw SwiftDataArchiveFailure.cancelled
        }
    }

    /// ensureDirectory prepays mkdir on the same protected ledger and retains created ownership.
    private func ensureDirectory(_ operation: UUID) async throws {
        try await observe()
        try validateAuthority(operation)
        guard descriptor < 0 else { return }
        guard let parent, rawInventoryStatus == .absent else {
            throw SwiftDataArchiveFailure.unsafePath
        }
        try await growDisk(by: SwiftDataArchiveDirectory.entryBytes)
        try validateAuthority(operation)
        try SwiftDataArchiveDirectory.validateHeldRoot(
            root      : parent.root,
            descriptor: parent.descriptor
        )
        do {
            try directoryCreation.createDirectory(
                parentDescriptor: parent.descriptor,
                name            : parent.name
            )
        } catch KeyedStorageFailure.io(let code) where code == EEXIST {
            // Another creator is not authority: observation must still validate/lock the child.
        }
        // Observation adopts any real child before cancellation checks and accounts files on failure.
        try await observe()
        try validate(operation)
    }

    private func finish(_ operation: UUID) {
        if active == operation { active = nil }
    }

    /// growDisk prepays the complete candidate while the old files remain charged.
    private func growDisk(by bytes: Int) async throws {
        let target = chargedBytes.addingReportingOverflow(bytes)
        guard !target.overflow else { throw SwiftDataArchiveFailure.accounting }
        guard try await resourceGovernorTarget.growObservedDisk(
            token,
            owner    : identity.addonID,
            fromBytes: chargedBytes,
            toBytes  : target.partialValue
        ) else { throw SwiftDataArchiveFailure.accounting }
        chargedBytes = target.partialValue
    }

    /// observe runs after failures too. Only complete safe scans may refund prior charges.
    /// Fully counted safe unknown entries still block framework access without hiding their size.
    private func observe() async throws {
        rawInventoryStatus = .blocked
        let inventory = await directoryInventory()
        let mayRefund = inventory.isComplete && !inventory.hasUnsafeEntries
        let observed = mayRefund ? inventory.bytes : max(
            chargedBytes,
            inventory.bytes
        )
        guard try await resourceGovernorTarget.reconcileObservedDisk(
            token,
            owner        : identity.addonID,
            fromBytes    : chargedBytes,
            measuredBytes: observed
        ) else {
            hasFault = true
            throw SwiftDataArchiveFailure.accounting
        }
        chargedBytes           = observed
        measuredBytes          = observed
        permitsFrameworkAccess = inventory.permitsFrameworkAccess && descriptor >= 0
        rawInventoryStatus     = inventory.permitsFrameworkAccess
            ? (descriptor >= 0 ? .complete : .absent) : .blocked
        hasFault               = !inventory.permitsFrameworkAccess
        guard inventory.permitsFrameworkAccess else { throw SwiftDataArchiveFailure.unsafePath }
    }

    /// directoryInventory adopts a checked child once and retains it before subsequent validation.
    private func directoryInventory() async -> SwiftDataArchiveInventory {
        var knownBytes = 0
        do {
            if let parent {
                try SwiftDataArchiveDirectory.validateHeldRoot(
                    root      : parent.root,
                    descriptor: parent.descriptor
                )
                if descriptor < 0 {
                    if let opened = try SwiftDataArchiveDirectory.openChild(
                        parent.descriptor,
                        name: parent.name
                    ) {
                        descriptor = opened
                    } else {
                        try SwiftDataArchiveDirectory.validateHeldRoot(
                            root      : parent.root,
                            descriptor: parent.descriptor
                        )
                        return SwiftDataArchiveInventory(
                            bytes            : 0,
                            isComplete       : true,
                            hasUnsafeEntries : false,
                            hasUnknownEntries: false
                        )
                    }
                }
                try SwiftDataArchiveDirectory.validateHeldRoot(
                    root      : parent.root,
                    descriptor: parent.descriptor
                )
            }
            let inventory = await observer.inventory(
                root      : root,
                descriptor: descriptor
            )
            // Parent identity may fail after an awaited scan; its already-known bytes remain owned.
            knownBytes = inventory.bytes
            if let parent {
                try SwiftDataArchiveDirectory.validateHeldRoot(
                    root      : parent.root,
                    descriptor: parent.descriptor
                )
            }
            return inventory
        } catch {
            return SwiftDataArchiveInventory(
                bytes            : max(
                    knownBytes,
                    parent.map {
                        SwiftDataArchiveDirectory.knownChildBytes(
                            $0.descriptor,
                            name: $0.name
                        )
                    } ?? 0
                ),
                isComplete       : false,
                hasUnsafeEntries : true,
                hasUnknownEntries: false
            )
        }
    }

    /// observeAfterFailure preserves accounting regardless of task cancellation or framework errors.
    private func observeAfterFailure(_ failure: any Error) async {
        do { try await observe() }
        catch { hasFault = true }
        if let failure = failure as? SwiftDataArchiveFailure {
            switch failure {
            case .corrupt, .futureFormat, .invalidGeneration, .accounting:
                hasFault = true
            default:
                break
            }
        }
    }
}
