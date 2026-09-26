//
//  AddonStorageCoordinator.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation

/// AddonStorageCoordinator gates normal persistence until the complete retained registry reconciles.
/// Its complete registry is immutable and includes disabled or uninstalled retained identities.
/// The host keeps this object and its governor alive across close/retry: the keyed ledger and
/// archive ledgers stay charged while logically closed. No backend or capability escapes.
actor AddonStorageCoordinator {
    enum Failure: Error, Equatable, Sendable {
        case invalidConfiguration
        case unavailable
        case busy
        case invalidOwner
    }

    /// CloseStatus distinguishes logical cleanup from accepted work still draining.
    /// Closed retains archive workers, parent/child locks and ledgers; it is not physical closure.
    /// A draining result requires the host to retry close after the active operation returns.
    enum CloseStatus: Equatable, Sendable {
        case closed
        case draining
    }

    /// Owner is an opaque capability for a fixed registry row in one readiness epoch.
    /// Acquisition does not grow a session table; another coordinator or epoch cannot use it.
    struct Owner: Hashable, Sendable {
        fileprivate let coordinatorID: UUID
        fileprivate let epoch        : UUID
        fileprivate let index        : Int
    }

    private struct BackendOwners: Sendable {
        let checkpoint: StateOwner
        let keyed     : KeyedStorageOwner
    }

    private struct BackendAccess: Sendable {
        let checkpoint: AddonStateStore
        let keyed     : AddonKeyedStorage
        let owners    : BackendOwners
    }

    /// ArchiveAccess retains only the fixed private backend and this accepted operation's binding.
    private struct ArchiveAccess: Sendable {
        let operation: Operation
        let archive  : SwiftDataArchive
        let addonID  : AddonID
    }

    private struct Operation: Equatable, Sendable {
        enum Kind: Equatable, Sendable {
            case starting
            case normal
            case closing
        }

        let id  : UUID
        let kind: Kind
    }

    // Includes three bounded root URLs, parent/operation state, fixed names/archive slots,
    // registry rows and overlapping backend-owner arrays. Each archive prepays its own lifetime.
    // The existing ordinary coordinator metadata convention is separate from protected ledgers.
    private static let shutdownMetadataBytes = max(
        1_024,
        4 * MemoryLayout<ArchiveShutdownContext>.stride
    )
    private static let fixedMetadataBytes = 24_576 + 256 + shutdownMetadataBytes
    private static let registrationBytes  = 3_072

    private let coordinatorID = UUID()
    private let checkpointRoot      : URL
    private let keyedRoot           : URL
    private let archiveRoot         : URL
    private let archiveNames        : [String]
    private let archiveObserver     : any SwiftDataArchiveObserving
    private let archiveRootToken    : ObservedDiskToken
    private let registrations       : [StateRegistration]
    /// resourceGovernorTarget exposes immutable assembly identity, never a storage capability.
    nonisolated var resourceGovernorTarget: ResourceGovernor { governor }

    private let governor            : ResourceGovernor
    private let resourceAccess      : any RuntimeResourceAccess
    private let keyedFileOperations : any KeyedStorageFileOperations
    private let checkpointDiskBudget: Int
    private let keyedDiskBudget     : Int
    private let metadata            : ResourceReservation

    private var archives              : [SwiftDataArchive?]
    private var archiveRootDescriptor = Int32(-1)
    private var archiveRootBytes      = 0
    private var archiveFlushCursor    = 0

    private var checkpointStore: AddonStateStore?
    private var keyedStore     : AddonKeyedStorage?
    private var backendOwners  : [BackendOwners] = []
    private var readinessEpoch : UUID?
    private var active         : Operation?
    private var isClosing      = true
    private var closeCleanupPending = false
    private var archiveShutdown: ArchiveShutdownContext?

    /// ArchiveShutdownContext survives terminal revocation and never replaces an accepted operation.
    private struct ArchiveShutdownContext: Sendable {
        let id             : UUID
        let runtime        : AddonRuntime
        let deadline       : Duration
        var phase          : ShutdownPhase
        var ticket         : AddonRuntime.ArchiveQuiescence?
        var cursor         : Int
        var unvisitedOwners: Int
        var runtimeCleanupPending = false
    }

    private init(
        checkpointRoot      : URL,
        keyedRoot           : URL,
        archiveRoot         : URL,
        archiveObserver     : any SwiftDataArchiveObserving,
        archiveRootToken    : ObservedDiskToken,
        registrations       : [StateRegistration],
        governor            : ResourceGovernor,
        resourceAccess      : any RuntimeResourceAccess,
        keyedFileOperations : any KeyedStorageFileOperations,
        checkpointDiskBudget: Int,
        keyedDiskBudget     : Int,
        metadata            : ResourceReservation
    ) {
        self.checkpointRoot       = checkpointRoot
        self.keyedRoot            = keyedRoot
        self.archiveRoot          = archiveRoot
        self.archiveObserver      = archiveObserver
        self.archiveRootToken     = archiveRootToken
        archiveNames              = registrations.map { Self.archiveName($0.identity) }
        archives                  = Array(
            repeating: nil,
            count    : registrations.count
        )
        // Metadata is prepaid; copy only bounded rows without retaining caller excess capacity.
        self.registrations        = registrations.map { $0 }
        self.governor             = governor
        self.resourceAccess       = resourceAccess
        self.keyedFileOperations  = keyedFileOperations
        self.checkpointDiskBudget = checkpointDiskBudget
        self.keyedDiskBudget      = keyedDiskBudget
        self.metadata             = metadata
    }

    deinit {
        if archiveRootDescriptor >= 0 { Darwin.close(archiveRootDescriptor) }
    }

    /// make validates and prepays bounded coordinator retention before constructing its tables.
    /// It opens no backend and returns unavailable. Empty and dynamic registries require
    /// separate host integration; passing a partial retained registry is never recovery policy.
    static func make(
        checkpointRoot      : URL,
        keyedRoot           : URL,
        archiveRoot         : URL,
        registrations       : [StateRegistration],
        governor            : ResourceGovernor,
        resourceAccess      : (any RuntimeResourceAccess)? = nil,
        keyedFileOperations : any KeyedStorageFileOperations = POSIXKeyedStorageFileOperations(),
        archiveObserver     : any SwiftDataArchiveObserving = NativeSwiftDataArchiveObserver(),
        checkpointDiskBudget: Int = 100 * 1_024 * 1_024,
        keyedDiskBudget     : Int = 100 * 1_024 * 1_024
    ) async throws -> AddonStorageCoordinator {
        try Task.checkCancellation()
        guard (1...256).contains(registrations.count) else {
            throw Failure.invalidConfiguration
        }
        try validateRootURL(checkpointRoot)
        try validateRootURL(keyedRoot)
        try validateRootURL(archiveRoot)
        // Scan bounded input without allocating a uniqueness table before admission.
        for index in registrations.indices {
            let registration = registrations[index]
            guard registration.maximumSchemaVersion > 0,
                  (1...512).contains(registration.identity.publisher.utf8.count),
                  !registrations[..<index].contains(where: { $0.identity == registration.identity }) else {
                throw Failure.invalidConfiguration
            }
            try validateRootURL(archiveRoot.appendingPathComponent(archiveName(registration.identity)))
        }
        let access = resourceAccess ?? governor
        guard access.resourceGovernorTarget === governor else {
            throw Failure.invalidConfiguration
        }
        let metadata = try await governor.admit(
            .state(bytes: Self.fixedMetadataBytes + registrations.count * Self.registrationBytes),
            owner: registrations[0].identity.addonID
        )
        var rootToken: ObservedDiskToken?
        do {
            try Task.checkCancellation()
            let token = try await governor.admitObservedDisk(
                bytes: 0,
                owner: registrations[0].identity.addonID
            )
            rootToken = token
            try Task.checkCancellation()
            return AddonStorageCoordinator(
                checkpointRoot      : checkpointRoot,
                keyedRoot           : keyedRoot,
                archiveRoot         : archiveRoot,
                archiveObserver     : archiveObserver,
                archiveRootToken    : token,
                registrations       : registrations,
                governor            : governor,
                resourceAccess      : access,
                keyedFileOperations : keyedFileOperations,
                checkpointDiskBudget: checkpointDiskBudget,
                keyedDiskBudget     : keyedDiskBudget,
                metadata            : metadata
            )
        } catch {
            // No descriptor or archive was constructed, so this token still measures zero.
            if let rootToken {
                try await governor.completeObservedDisk(
                    rootToken,
                    owner: registrations[0].identity.addonID
                )
            }
            try await governor.release(
                metadata.id,
                owner: metadata.owner
            )
            throw error
        }
    }

    /// archiveName binds one fixed namespace to its verified publisher and addon, not executable digest.
    private static func archiveName(_ identity: VerifiedAddonIdentity) -> String {
        KeyedStorageRecord.hex(KeyedStorageRecord.namespaceDigest(identity))
    }

    /// validateRootURL bounds the complete retained URL, not only its decoded filesystem path.
    /// Host roots are absolute file URLs without a retained base, query or fragment. Backend
    /// traversal still validates real ownership, permissions, symlinks and held root identity.
    private static func validateRootURL(_ root: URL) throws {
        guard root.baseURL == nil,
              root.isFileURL,
              root.absoluteString.utf8.count <= 4_096,
              root.query == nil,
              root.fragment == nil,
              root.path.hasPrefix("/") else {
            throw Failure.invalidConfiguration
        }
    }

    /// start inventories all archives before checkpoint recovery and keyed-ledger reconciliation.
    /// Every successful backend is retained before post-await authority checks, including an
    /// open that finished after close was requested. Failure leaves the global gate unavailable.
    func start() async throws {
        try Task.checkCancellation()
        guard archiveShutdown == nil else { throw Failure.unavailable }
        guard active == nil else { throw Failure.busy }
        guard readinessEpoch == nil else { return }
        let operation = Operation(
            id  : UUID(),
            kind: .starting
        )
        active = operation
        isClosing = false
        defer { finish(operation) }
        do {
            guard try await closeBackends(validatingStartup: operation) == .closed else {
                throw Failure.busy
            }
            try validateStartup(operation)
            closeCleanupPending = true
            try await establishArchiveInventory(operation)
            try validateInventoriedStartup(operation)
            checkpointStore = try await AddonStateStore.open(
                root         : checkpointRoot,
                registrations: registrations,
                governor     : governor,
                diskBudget   : checkpointDiskBudget
            )
            try validateInventoriedStartup(operation)
            if let keyedStore {
                try await keyedStore.reopen(root: keyedRoot)
            } else {
                keyedStore = try await AddonKeyedStorage.open(
                    root          : keyedRoot,
                    registrations : registrations.map { KeyedStorageRegistration(identity: $0.identity) },
                    governor      : governor,
                    diskBudget    : keyedDiskBudget,
                    resourceAccess: resourceAccess,
                    fileOperations: keyedFileOperations
                )
            }
            try validateInventoriedStartup(operation)
            guard let checkpointStore, let keyedStore else { throw Failure.unavailable }
            backendOwners.reserveCapacity(registrations.count)
            for registration in registrations {
                let checkpointOwner = try await checkpointStore.owner(for: registration.identity)
                try validateInventoriedStartup(operation)
                let keyedOwner = try await keyedStore.owner(for: registration.identity)
                try validateInventoriedStartup(operation)
                backendOwners.append(BackendOwners(
                    checkpoint: checkpointOwner,
                    keyed     : keyedOwner
                ))
            }
            readinessEpoch = operation.id
        } catch {
            let startupFailure = error
            invalidateReadiness()
            // Cleanup is allowed after cancellation. References remain private and retained if
            // cleanup throws or drains; a later close/start retries them before opening anything.
            _ = try await closeBackends()
            throw startupFailure
        }
    }

    /// establishArchiveInventory keeps every established ledger even when another row blocks readiness.
    /// The root allowance has known host ownership; unknown outer children do not acquire that owner.
    private func establishArchiveInventory(_ operation: Operation) async throws {
        try validateStartup(operation)
        if archiveRootDescriptor < 0 {
            // Retain this open description before any await. C1 duplicates it; restart must reuse it.
            archiveRootDescriptor = try KeyedStorageDirectory.openRoot(archiveRoot)
        }
        guard try await governor.reconcileObservedDisk(
            archiveRootToken,
            owner        : registrations[0].identity.addonID,
            fromBytes    : archiveRootBytes,
            measuredBytes: SwiftDataArchiveDirectory.entryBytes
        ) else { throw SwiftDataArchiveFailure.accounting }
        archiveRootBytes = SwiftDataArchiveDirectory.entryBytes
        try validateStartup(operation)
        try validateArchiveRoot()
        var complete = archiveOuterInventoryIsComplete()
        for index in registrations.indices {
            try validateStartup(operation)
            try validateArchiveRoot()
            do {
                if let archive = archives[index] {
                    _ = try await archive.reconcile()
                } else {
                    let archive = try await SwiftDataArchive.discover(
                        identity        : registrations[index].identity,
                        parentRoot      : archiveRoot,
                        parentDescriptor: archiveRootDescriptor,
                        governor        : governor,
                        observer        : archiveObserver
                    )
                    // Discovery may return after cancellation with newly established disk ownership.
                    archives[index] = archive
                }
            } catch {
                // A local failure cannot hide later known owners while parent/epoch remain valid.
                complete = false
            }
            try validateStartup(operation)
            try validateArchiveRoot()
            complete = archiveOuterInventoryIsComplete() && complete
            if let archive = archives[index] {
                let inventory = await archive.inventoryStatus()
                try validateStartup(operation)
                try validateArchiveRoot()
                complete = archiveOuterInventoryIsComplete() && complete
                guard inventory == .absent || inventory == .complete else {
                    complete = false
                    continue
                }
            } else {
                complete = false
            }
        }
        guard complete else { throw Failure.unavailable }
    }

    /// validateInventoriedStartup rechecks the outer barrier after checkpoint/keyed suspension.
    /// A late unknown namespace cannot publish readiness from an earlier complete root scan.
    private func validateInventoriedStartup(_ operation: Operation) throws {
        try validateStartup(operation)
        try validateArchiveRoot()
        guard archiveOuterInventoryIsComplete() else { throw Failure.unavailable }
    }

    /// validateArchiveRoot refuses replacement without closing the held root or refunding its ledger.
    private func validateArchiveRoot() throws {
        guard archiveRootDescriptor >= 0 else { throw Failure.unavailable }
        try SwiftDataArchiveDirectory.validateHeldRoot(
            root      : archiveRoot,
            descriptor: archiveRootDescriptor
        )
    }

    /// archiveOuterInventoryIsComplete checks bounded names and present private directories without links.
    /// Each known child's C1 still owns recursive inventory; unknown entries acquire no attribution.
    private func archiveOuterInventoryIsComplete() -> Bool {
        var complete = true
        do {
            try validateArchiveRoot()
            try KeyedStorageDirectory.entries(
                archiveRootDescriptor,
                maximumCount    : 256,
                maximumNameBytes: 64
            ) { name in
                guard archiveNames.contains(name) else {
                    complete = false
                    return
                }
                // A registered name may have become a link, file or nonprivate directory while
                // a backend admission was suspended. The existing helper checks no-follow type,
                // current-user ownership and mode; this is not another recursive inventory.
                guard let child = try KeyedStorageDirectory.child(
                    archiveRootDescriptor,
                    name: name
                ) else {
                    complete = false
                    return
                }
                Darwin.close(child)
            }
            try validateArchiveRoot()
        } catch {
            complete = false
        }
        return complete
    }

    /// ShutdownPhase cannot leave terminal once ordinary owner epochs have been revoked.
    enum ShutdownPhase: Equatable, Sendable { case acquiring, ready, terminal }

    /// ShutdownProgress reports finite pass position and conservative known cleanup obligations.
    struct ShutdownProgress: Equatable, Sendable {
        let phase          : ShutdownPhase
        let unvisitedOwners: Int
        let cleanupPending : Bool
    }

    /// ShutdownStepResult returns at most one accepted attempt without claiming the pass was durable.
    enum ShutdownStepResult: Equatable, Sendable {
        case busy
        case exhausted
        case windowClosed
        case failed(
            owner          : AddonID,
            failure        : ArchiveFlushFailure,
            accepted       : Bool,
            unvisitedOwners: Int
        )
        case committed(
            owner          : AddonID,
            outcome        : SwiftDataArchiveSaveOutcome,
            unvisitedOwners: Int
        )
    }

    /// beginArchiveShutdown revokes ordinary capabilities before its first runtime hop.
    /// An existing accepted operation keeps its ID and private access until its own finish path.
    func beginArchiveShutdown(
        runtime       : AddonRuntime,
        until deadline: Duration
    ) async throws -> ShutdownProgress {
        if let context = archiveShutdown {
            guard context.runtime === runtime, context.deadline == deadline else {
                throw ArchiveFlushFailure.coordinator(.invalidConfiguration)
            }
            return shutdownProgress
        }
        guard deadline >= .zero else { throw ArchiveFlushFailure.coordinator(.invalidConfiguration) }
        guard readinessEpoch != nil, !isClosing else { throw ArchiveFlushFailure.coordinator(.unavailable) }
        let contextID = UUID()
        archiveShutdown = ArchiveShutdownContext(
            id             : contextID,
            runtime        : runtime,
            deadline       : deadline,
            phase          : .acquiring,
            ticket         : nil,
            cursor         : archiveFlushCursor,
            unvisitedOwners: registrations.count
        )
        invalidateReadiness()
        do {
            let ticket = try await runtime.beginArchiveQuiescence(until: deadline)
            // Retain even a late successful capability before testing terminal context authority.
            archiveShutdown?.ticket = ticket
            if archiveShutdown?.id == contextID, archiveShutdown?.phase == .acquiring {
                archiveShutdown?.phase = .ready
            } else {
                let stopped = await runtime.requestStop()
                archiveShutdown?.runtimeCleanupPending = stopped.cleanupPending
            }
            return shutdownProgress
        } catch {
            let bounded = Self.boundedArchiveFlushFailure(error)
            archiveShutdown?.phase = .terminal
            let stopped = await runtime.requestStop()
            archiveShutdown?.runtimeCleanupPending = stopped.cleanupPending
            _ = requestClose()
            throw bounded
        }
    }

    private var shutdownProgress: ShutdownProgress {
        ShutdownProgress(
            phase          : archiveShutdown?.phase ?? .terminal,
            unvisitedOwners: archiveShutdown?.unvisitedOwners ?? 0,
            cleanupPending : closeCleanupPending || active != nil
                || archiveShutdown?.runtimeCleanupPending == true
        )
    }

    /// flushNextShutdownArchive visits each fixed row at most once, returning after one accepted attempt.
    /// Busy consumes no row; a known commit survives concurrent terminal context revocation.
    func flushNextShutdownArchive() async -> ShutdownStepResult {
        guard let context = archiveShutdown else { return .windowClosed }
        guard context.phase != .terminal else { return .windowClosed }
        guard context.phase == .ready, active == nil else { return .busy }
        guard let ticket = context.ticket else { return .windowClosed }
        guard context.unvisitedOwners > 0 else { return .exhausted }
        let operation = Operation(
            id  : UUID(),
            kind: .normal
        )
        active = operation
        defer { finish(operation) }
        while let current = archiveShutdown, current.id == context.id,
            current.phase == .ready, current.unvisitedOwners > 0
        {
            let index = current.cursor
            let owner = registrations[index].identity.addonID
            guard let archive = archives[index] else {
                consumeShutdownRow(contextID: context.id)
                continue
            }
            let attempt = await context.runtime.saveQuiescingArchive(
                owner     : owner,
                to        : archive,
                quiescence: ticket
            )
            switch attempt {
            case .busy:
                return archiveShutdown?.phase == .ready ? .busy : .windowClosed
            case .windowClosed:
                archiveShutdown?.phase = .terminal
                return .windowClosed
            case .skipped:
                consumeShutdownRow(contextID: context.id)
                guard archiveShutdown?.id == context.id, archiveShutdown?.phase == .ready else {
                    return .windowClosed
                }
            case .refused(let failure):
                consumeShutdownRow(contextID: context.id)
                return .failed(
                    owner          : owner,
                    failure        : Self.shutdownFailure(failure),
                    accepted       : false,
                    unvisitedOwners: archiveShutdown?.unvisitedOwners ?? 0
                )
            case .failed(let failure):
                consumeShutdownRow(contextID: context.id)
                return .failed(
                    owner          : owner,
                    failure        : Self.shutdownFailure(failure),
                    accepted       : true,
                    unvisitedOwners: archiveShutdown?.unvisitedOwners ?? 0
                )
            case .committed(let outcome):
                consumeShutdownRow(contextID: context.id)
                return .committed(
                    owner          : owner,
                    outcome        : outcome,
                    unvisitedOwners: archiveShutdown?.unvisitedOwners ?? 0
                )
            }
        }
        return archiveShutdown?.phase == .ready ? .exhausted : .windowClosed
    }

    /// consumeShutdownRow updates only scalar progress, preserving a concurrent terminal phase.
    private func consumeShutdownRow(contextID: UUID) {
        guard let current = archiveShutdown, current.id == contextID, current.unvisitedOwners > 0 else {
            return
        }
        archiveShutdown?.cursor = (current.cursor + 1) % registrations.count
        archiveShutdown?.unvisitedOwners = current.unvisitedOwners - 1
    }

    /// shutdownFailure maps the runtime scalar result into the existing bounded coordinator vocabulary.
    private static func shutdownFailure(_ failure: AddonRuntime.ShutdownArchiveFailure) -> ArchiveFlushFailure
    {
        switch failure {
        case .runtime(let failure): return .runtime(failure)
        case .archive(let failure): return .archive(failure)
        case .cancelled: return .cancelled
        case .unavailable: return .unavailable
        }
    }

    /// finishArchiveShutdown obtains logical runtime stop without awaiting any backend cleanup.
    /// The coordinator becomes terminal before the actor hop, so no later row can begin meanwhile.
    func finishArchiveShutdown() async -> ShutdownProgress {
        archiveShutdown?.phase = .terminal
        if let runtime = archiveShutdown?.runtime {
            let stopped = await runtime.requestStop()
            archiveShutdown?.runtimeCleanupPending = stopped.cleanupPending
        }
        _ = requestClose()
        return shutdownProgress
    }

    /// requestClose revokes coordinator admission synchronously, never the separate runtime actor ticket.
    /// A later close/finish obtains runtime stop and close retries backend draining explicitly.
    func requestClose() -> CloseStatus {
        archiveShutdown?.phase = .terminal
        invalidateReadiness()
        if active != nil { closeCleanupPending = true }
        return closeCleanupPending || archiveShutdown?.runtimeCleanupPending == true ? .draining : .closed
    }

    /// close invalidates readiness before any suspension and never waits in a caller queue.
    /// Accepted work may finish under backend commit semantics. Draining is not closed; the
    /// host retries after that work returns. A shutdown context drains runtime cleanup before backends;
    /// a pending runtime drain remains draining even when backend suspension is complete.
    func close() async throws -> CloseStatus {
        // Capture before requestClose: a previously terminalized/acquiring context still needs this hop.
        let runtime = archiveShutdown?.runtime
        _ = requestClose()
        if let runtime {
            let stopped = await runtime.requestStop()
            archiveShutdown?.runtimeCleanupPending = stopped.cleanupPending
        }
        guard active == nil else { return .draining }
        let operation = Operation(
            id  : UUID(),
            kind: .closing
        )
        active = operation
        defer { finish(operation) }
        if let runtime {
            await runtime.stop()
            let stopped = await runtime.requestStop()
            archiveShutdown?.runtimeCleanupPending = stopped.cleanupPending
        }
        let status = try await closeBackends()
        if archiveShutdown?.runtimeCleanupPending == true { return .draining }
        return status
    }

    /// owner returns a fixed capability only after archive inventory and both normal backends are ready.
    func owner(for identity: VerifiedAddonIdentity) throws -> Owner {
        try available()
        guard let index = registrations.firstIndex(where: { $0.identity == identity }),
              let readinessEpoch else {
            throw Failure.invalidOwner
        }
        return Owner(
            coordinatorID: coordinatorID,
            epoch        : readinessEpoch,
            index        : index
        )
    }

    /// ArchiveFlushResult returns at most one known commit without exposing a private backend.
    enum ArchiveFlushResult: Equatable, Sendable {
        case noCommit
        case committed(
            owner  : AddonID,
            outcome: SwiftDataArchiveSaveOutcome
        )
    }

    /// ArchiveFlushFailure bounds uncommitted errors without retaining platform payloads.
    enum ArchiveFlushFailure: Error, Equatable, Sendable {
        case coordinator(Failure)
        case runtime(AddonFailure.Code)
        case archive(SwiftDataArchiveFailure)
        case cancelled
        case unavailable
    }

    /// flushNextArchive attempts at most one pending owner, then returns control to the host event driver.
    /// A noCommit result does not promise every owner is clean: unchanged failed attempts remain retryRequired.
    func flushNextArchive(runtime: AddonRuntime) async throws -> ArchiveFlushResult {
        do {
            try Task.checkCancellation()
            try available()
            let operation = Operation(
                id  : UUID(),
                kind: .normal
            )
            active = operation
            defer { finish(operation) }
            for offset in registrations.indices {
                let index = (archiveFlushCursor + offset) % registrations.count
                let state = await runtime.archiveFlushState(identity: registrations[index].identity)
                try validateStartup(operation)
                guard state == .pending else { continue }
                archiveFlushCursor = (index + 1) % registrations.count
                guard let archive = archives[index], let readinessEpoch else { throw Failure.unavailable }
                let owner = Owner(
                    coordinatorID: coordinatorID,
                    epoch        : readinessEpoch,
                    index        : index
                )
                let access = ArchiveAccess(
                    operation: operation,
                    archive  : archive,
                    addonID  : registrations[index].identity.addonID
                )
                try await prepareArchiveOperation(
                    access,
                    owner       : owner,
                    runtime     : runtime,
                    startArchive: false
                )
                try validateArchiveOperation(
                    operation,
                    owner: owner
                )
                let outcome = try await runtime.savePendingArchive(
                    owner: access.addonID,
                    to   : archive
                )
                if let outcome {
                    return .committed(
                        owner  : access.addonID,
                        outcome: outcome
                    )
                }
                return .noCommit
            }
            return .noCommit
        } catch {
            throw Self.boundedArchiveFlushFailure(error)
        }
    }

    /// boundedArchiveFlushFailure drops arbitrary backend descriptions and userInfo at the facade boundary.
    private static func boundedArchiveFlushFailure(_ error: any Error) -> ArchiveFlushFailure {
        if let failure = error as? Failure { return .coordinator(failure) }
        if let failure = error as? AddonFailure { return .runtime(failure.code) }
        if let failure = error as? SwiftDataArchiveFailure { return .archive(failure) }
        if error is CancellationError { return .cancelled }
        return .unavailable
    }

    /// saveArchive forwards one verified owner's runtime generation without exposing its backend.
    /// Once the runtime returns its known commit, cleanup cannot relabel it as a rejected write.
    func saveArchive(
        owner  : Owner,
        runtime: AddonRuntime
    ) async throws -> SwiftDataArchiveSaveOutcome {
        let access = try claimArchiveOperation(owner: owner)
        defer { finish(access.operation) }
        try await prepareArchiveOperation(
            access,
            owner  : owner,
            runtime: runtime
        )
        try validateArchiveOperation(
            access.operation,
            owner: owner
        )
        return try await runtime.saveArchive(
            owner: access.addonID,
            to   : access.archive
        )
    }

    /// restoreArchive returns only a scalar runtime result from the privately retained archive.
    /// A completed canonical activation survives close/cancellation while its result is returning.
    func restoreArchive(
        owner  : Owner,
        runtime: AddonRuntime
    ) async throws -> AddonRuntime.ArchiveRestorationResult {
        let access = try claimArchiveOperation(owner: owner)
        defer { finish(access.operation) }
        try await prepareArchiveOperation(
            access,
            owner  : owner,
            runtime: runtime
        )
        try validateArchiveOperation(
            access.operation,
            owner: owner
        )
        return try await runtime.restoreArchive(
            owner: access.addonID,
            from : access.archive
        )
    }

    /// claimArchiveOperation authenticates the current fixed owner before borrowing its retained slot.
    private func claimArchiveOperation(owner: Owner) throws -> ArchiveAccess {
        try Task.checkCancellation()
        try available()
        try validateOwner(owner)
        guard let archive = archives[owner.index] else { throw Failure.unavailable }
        let operation = Operation(
            id  : UUID(),
            kind: .normal
        )
        active = operation
        return ArchiveAccess(
            operation: operation,
            archive  : archive,
            addonID  : registrations[owner.index].identity.addonID
        )
    }

    /// prepareArchiveOperation checks runtime binding before provisioning, then validates return authority.
    /// The caller owns the operation through the actual runtime call and finishes it nonthrowingly.
    private func prepareArchiveOperation(
        _ access    : ArchiveAccess,
        owner       : Owner,
        runtime     : AddonRuntime,
        startArchive: Bool = true
    ) async throws {
        try await runtime.validateArchiveBinding(
            owner  : access.addonID,
            archive: access.archive
        )
        try validateArchiveOperation(
            access.operation,
            owner: owner
        )
        if startArchive { _ = try await access.archive.start() }
        try validateArchiveOperation(
            access.operation,
            owner: owner
        )
    }

    /// validateArchiveOperation rejects late preparation without undoing an already returned runtime result.
    private func validateArchiveOperation(
        _ operation: Operation,
        owner      : Owner
    ) throws {
        try Task.checkCancellation()
        guard active == operation, !isClosing else { throw Failure.unavailable }
        try validateOwner(owner)
    }

    /// read forwards host-selected keyed access without exposing its underlying owner capability.
    func read(
        key         : String,
        owner       : Owner,
        storageClass: KeyedStorageClass = .data
    ) async throws -> Data? {
        try await perform(owner: owner) { access in
            try await access.keyed.read(
                key         : key,
                owner       : access.owners.keyed,
                storageClass: storageClass
            )
        }
    }

    /// write retains the backend's atomic visibility and durability-uncertainty semantics.
    /// A close/cancellation after backend commit cannot roll it back, even if the final
    /// coordinator authority check refuses to return a normal result.
    func write(
        _ value     : Data,
        key         : String,
        owner       : Owner,
        storageClass: KeyedStorageClass = .data
    ) async throws {
        try await perform(owner: owner) { access in
            try await access.keyed.write(
                value,
                key         : key,
                owner       : access.owners.keyed,
                storageClass: storageClass
            )
        }
    }

    /// remove deletes only an explicitly selected key through a current coordinator owner.
    func remove(
        key         : String,
        owner       : Owner,
        storageClass: KeyedStorageClass = .data
    ) async throws {
        try await perform(owner: owner) { access in
            try await access.keyed.remove(
                key         : key,
                owner       : access.owners.keyed,
                storageClass: storageClass
            )
        }
    }

    /// KeyedRequestRefusal carries only bounded pre-call or read failures, never backend error text.
    enum KeyedRequestRefusal: Equatable, Sendable {
        case invalidRequest, invalidOwner, unavailable, busy, cancelled
        case readFailed(AddonFailure.Code)
    }

    /// KeyedRequestResult preserves known mutation success independently of reply authority.
    /// outcomeUnknown neither proves mutation nor permits automatic replay.
    enum KeyedRequestResult: Equatable, Sendable {
        case read(Data?)
        case acknowledged
        case refused(KeyedRequestRefusal)
        case outcomeUnknown
    }

    /// executeKeyedRequest uses one current host capability and the fixed data namespace.
    /// The caller prepays request/result retention through response handoff. This method
    /// adds no raw-frame/profile authorization, reply credit or retained request history.
    func executeKeyedRequest(
        _ request: StorageRequest,
        owner    : Owner
    ) async -> KeyedRequestResult {
        do {
            try Task.checkCancellation()
            try available()
            try validateOwner(owner)
        } catch {
            return .refused(Self.keyedRequestPreflightFailure(error))
        }
        do {
            try request.validate()
        } catch {
            return .refused(.invalidRequest)
        }
        guard let checkpointStore, let keyedStore else { return .refused(.unavailable) }
        let access = BackendAccess(
            checkpoint: checkpointStore,
            keyed     : keyedStore,
            owners    : backendOwners[owner.index]
        )
        let operation = Operation(
            id  : UUID(),
            kind: .normal
        )
        active = operation
        defer { finish(operation) }

        switch request.operation {
        case .read:
            do {
                let value = try await access.keyed.read(
                    key         : request.key,
                    owner       : access.owners.keyed,
                    storageClass: .data
                )
                do {
                    try Task.checkCancellation()
                    guard active == operation, !isClosing else { throw Failure.unavailable }
                    try validateOwner(owner)
                } catch {
                    return .refused(Self.keyedRequestPreflightFailure(error))
                }
                guard (value?.count ?? 0) <= StorageFrameCodec.maximumValueBytes else {
                    return .refused(.readFailed(.invalidPayload))
                }
                return .read(value)
            } catch {
                return .refused(Self.keyedRequestReadFailure(error))
            }
        case .write:
            guard let value = request.value else { return .refused(.invalidRequest) }
            do {
                try await access.keyed.write(
                    value,
                    key         : request.key,
                    owner       : access.owners.keyed,
                    storageClass: .data
                )
                return .acknowledged
            } catch {
                // Handoff occurred. No backend acceptance/commit receipt proves retry safety.
                return .outcomeUnknown
            }
        case .remove:
            do {
                try await access.keyed.remove(
                    key         : request.key,
                    owner       : access.owners.keyed,
                    storageClass: .data
                )
                return .acknowledged
            } catch {
                return .outcomeUnknown
            }
        }
    }

    /// keyedRequestPreflightFailure maps actor-local refusal without retaining error payloads.
    private static func keyedRequestPreflightFailure(_ error: any Error) -> KeyedRequestRefusal {
        if error is CancellationError { return .cancelled }
        guard let failure = error as? Failure else { return .invalidRequest }
        switch failure {
        case .busy: return .busy
        case .invalidOwner: return .invalidOwner
        case .unavailable, .invalidConfiguration: return .unavailable
        }
    }

    /// keyedRequestReadFailure is intentionally separate from mutation handling: no write
    /// was requested, so a read can return a bounded refusal without asserting commit state.
    private static func keyedRequestReadFailure(_ error: any Error) -> KeyedRequestRefusal {
        if error is CancellationError { return .cancelled }
        if let failure = error as? AddonFailure { return .readFailed(failure.code) }
        guard let failure = error as? KeyedStorageFailure else { return .readFailed(.dependencyUnavailable) }
        switch failure {
        case .invalidOwner, .invalidTicket, .closed:
            return .readFailed(.sessionRevoked)
        case .busy, .quotaExceeded:
            return .readFailed(.resourceDenied)
        case .invalidKey, .oversized:
            return .readFailed(.invalidPayload)
        case .futureFormat:
            return .readFailed(.versionConflict)
        case .invalidConfiguration, .unsafePath, .unrecognizedEntry, .corrupt, .staleRevision,
            .cleanupRequired, .committedDurabilityUncertain, .io:
            return .readFailed(.dependencyUnavailable)
        }
    }

    /// readCheckpoint returns checkpoint data only if readiness survives its backend await.
    func readCheckpoint(owner: Owner) async throws -> StateCheckpoint? {
        try await perform(owner: owner) { access in
            try await access.checkpoint.read(owner: access.owners.checkpoint)
        }
    }

    /// writeCheckpoint uses the registration's existing schema and checkpoint size limits.
    func writeCheckpoint(
        _ value      : Data,
        schemaVersion: UInt32,
        owner        : Owner
    ) async throws {
        try await perform(owner: owner) { access in
            try await access.checkpoint.write(
                value,
                schemaVersion: schemaVersion,
                owner        : access.owners.checkpoint
            )
        }
    }

    /// perform owns one already-prepaid operation row until backend work and refunds finish.
    /// No capability or result crosses a suspension without checking the readiness epoch again.
    private func perform<Result: Sendable>(
        owner: Owner,
        body : @Sendable (BackendAccess) async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        try available()
        try validateOwner(owner)
        guard let checkpointStore, let keyedStore else { throw Failure.unavailable }
        let access = BackendAccess(
            checkpoint: checkpointStore,
            keyed     : keyedStore,
            owners    : backendOwners[owner.index]
        )
        let operation = Operation(
            id  : UUID(),
            kind: .normal
        )
        active = operation
        defer { finish(operation) }
        let result = try await body(access)
        try Task.checkCancellation()
        guard active == operation, !isClosing else { throw Failure.unavailable }
        try validateOwner(owner)
        return result
    }

    /// closeBackends preserves every backend reference until its cleanup confirms closure.
    /// The checkpoint object is disposable after close; keyed and archive ledgers are retained.
    private func closeBackends(validatingStartup operation: Operation? = nil) async throws -> CloseStatus {
        closeCleanupPending = true
        for archive in archives {
            if let archive {
                _ = await archive.suspend()
                if let operation { try validateStartup(operation) }
            }
        }
        if let checkpointStore {
            try await checkpointStore.close()
            self.checkpointStore = nil
            if let operation { try validateStartup(operation) }
        }
        if let keyedStore {
            let status = try await keyedStore.close()
            if let operation { try validateStartup(operation) }
            guard status == .closed else { return .draining }
        }
        closeCleanupPending = false
        return .closed
    }

    /// available rejects new work during startup, shutdown or a competing accepted operation.
    private func available() throws {
        guard !isClosing, readinessEpoch != nil else { throw Failure.unavailable }
        guard active == nil else { throw Failure.busy }
    }

    /// validateOwner authenticates a capability without allocating or extending owner history.
    private func validateOwner(_ owner: Owner) throws {
        guard owner.coordinatorID == coordinatorID,
              owner.epoch == readinessEpoch,
              backendOwners.indices.contains(owner.index) else {
            throw Failure.invalidOwner
        }
    }

    /// validateStartup prevents close or cancellation from publishing a late backend result.
    private func validateStartup(_ operation: Operation) throws {
        try Task.checkCancellation()
        guard active == operation, !isClosing else { throw Failure.unavailable }
    }

    /// invalidateReadiness revokes all capabilities without retaining historical tombstones.
    private func invalidateReadiness() {
        readinessEpoch = nil
        backendOwners = []
        isClosing = true
    }

    /// finish relinquishes only the exact operation that claimed the bounded admission row.
    private func finish(_ operation: Operation) {
        if active == operation { active = nil }
    }
}
