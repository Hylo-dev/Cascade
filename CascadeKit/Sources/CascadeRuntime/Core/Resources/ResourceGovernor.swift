//
//  ResourceGovernor.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// ResourceGovernor keeps the host-owned admission bookkeeping. A reservation is not a sandbox
/// or proof of process termination. The runtime releases process charges after actual exit.
/// Native CPU/footprint observation is a separate, launcher-qualified boundary.
public actor ResourceGovernor {

    private struct Entry {

        let reservation        : ResourceReservation
        var charges            : [ResourceDimension: Int]
        var statePayloadBytes  : Int?
        var memoryPayloadBytes : Int?
        let retainedAssetSecret: UUID?
        let observedDiskSecret : UUID?
    }

    private let retainedAssetLifetime = UUID()
    private let observedDiskLifetime  = UUID()

    private let policy: ResourcePolicy

    private var entries                   : [UUID: Entry] = [:]
    private var totals                    : [ResourceDimension: Int] = [:]
    private var owners                    : [AddonID: [ResourceDimension: Int]] = [:]
    private var localFileWorkspaceLifetime: FileWorkspaceNamespaceLifetime?
#if DEBUG
    /// assetTransferRefundFailures lets a focused test inject a protected-refund failure through
    /// the real disposal seam. It carries no policy and production code never arms it.
    private var assetTransferRefundFailures  = 0
    private var assetTransferRefundAttempts : UInt64 = 0
    private var assetTransferRefundSuccesses: UInt64 = 0
    private var lastAssetTransferRefund     : UUID?
#endif

    public init(policy: ResourcePolicy = ResourcePolicy()) { self.policy = policy }

    /// fileWorkspaceLifetime returns the process-wide lifetime for the one local app shelf.
    func fileWorkspaceLifetime(
        directory: URL,
        owner    : AddonID
    ) throws -> FileWorkspaceNamespaceLifetime {
        if let localFileWorkspaceLifetime {
            guard localFileWorkspaceLifetime.directory == directory.standardizedFileURL,
                  localFileWorkspaceLifetime.owner == owner
            else {
                throw FileWorkspaceError.interrupted
            }
            return localFileWorkspaceLifetime
        }

        let lifetime = FileWorkspaceNamespaceLifetime(
            directory: directory,
            owner    : owner,
            resources: self
        )
        localFileWorkspaceLifetime = lifetime
        return lifetime
    }

    public func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) throws -> ResourceReservation {
        let charges            = try policy.charges(for: request)
        let reservation        = ResourceReservation(id: UUID(), owner: owner)
        let statePayloadBytes : Int?
        let memoryPayloadBytes: Int?
        if case .state(let bytes) = request {
            statePayloadBytes = bytes
        } else {
            statePayloadBytes = nil
        }
        if case .temporaryMemory(let bytes) = request {
            memoryPayloadBytes = bytes
        } else {
            memoryPayloadBytes = nil
        }

        return try insert(
            reservation        : reservation,
            charges            : charges,
            statePayloadBytes  : statePayloadBytes,
            memoryPayloadBytes : memoryPayloadBytes,
            retainedAssetSecret: nil
        )
    }

    private func insert(
        reservation        : ResourceReservation,
        charges            : [ResourceDimension: Int],
        statePayloadBytes  : Int?,
        memoryPayloadBytes : Int? = nil,
        retainedAssetSecret: UUID?,
        observedDiskSecret : UUID? = nil
    ) throws -> ResourceReservation {
        let owner = reservation.owner
        if charges[.diskBytes, default: 0] > 0 {
            try requireDiskGrowthEligibility(owner: owner)
        }

        for (dimension, amount) in charges {
            // A discovery token prepays metadata without requesting any disk growth.
            // It must remain available to record existing files even under prior debt.
            if observedDiskSecret != nil, amount == 0,
               dimension == .diskStateBytes || dimension == .diskBytes {
                continue
            }
            guard amount <= policy.ceiling(dimension, perOwner: false) - totals[dimension, default: 0],
                  amount <= policy.ceiling(dimension, perOwner: true)
                    - owners[owner, default: [:]][dimension, default: 0]
            else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "The resource budget is currently full."
                )
            }
        }

        entries[reservation.id] = Entry(
            reservation        : reservation,
            charges            : charges,
            statePayloadBytes  : statePayloadBytes,
            memoryPayloadBytes : memoryPayloadBytes,
            retainedAssetSecret: retainedAssetSecret,
            observedDiskSecret : observedDiskSecret
        )
        for (dimension, amount) in charges {
            totals[dimension, default: 0] += amount
            owners[owner, default: [:]][dimension, default: 0] += amount
        }
        return reservation
    }

    /// reduceStateReservation returns unused state payload capacity without changing identity or metadata.
    /// Validation and all three accounting updates are synchronous, so this also works at full capacity.
    /// A false result is an unchanged reservation, including when another operation already released it.
    public func reduceStateReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        toBytes bytes  : Int
    ) -> Bool {
        guard bytes >= 0,
              var entry = entries[reservationID],
              entry.reservation.owner == owner,
              let currentBytes = entry.statePayloadBytes,
              bytes <= currentBytes
        else { return false }

        let returnedBytes                  = currentBytes - bytes
        entry.statePayloadBytes            = bytes
        entry.charges[.retainedStateBytes] = bytes + ResourcePolicy.reservationCharge
        entries[reservationID]             = entry
        totals[.retainedStateBytes, default: 0] -= returnedBytes
        owners[owner, default: [:]][.retainedStateBytes, default: 0] -= returnedBytes
        return true
    }

    /// resizeStateReservation atomically changes the payload charged to one canonical state reservation.
    ///
    /// The expected byte count rejects a stale size assumption, but it is not an authority generation.
    /// Callers must separately serialize and revalidate their operation or epoch across suspension points.
    /// A completed resize also grants no right to roll back after that operation loses ownership.
    func resizeStateReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        fromBytes      : Int,
        toBytes        : Int
    ) throws -> Bool {
        guard var entry = entries[reservationID] else { return false }
        guard entry.reservation.owner == owner else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "The reservation belongs to another addon."
            )
        }
        guard let currentBytes = entry.statePayloadBytes, currentBytes == fromBytes else { return false }

        let desiredCharges = try policy.charges(for: .state(bytes: toBytes))
        let dimension      = ResourceDimension.retainedStateBytes
        let desiredCharge  = desiredCharges[dimension, default: 0]
        let currentCharge  = entry.charges[dimension, default: 0]
        let chargeDelta    = desiredCharge - currentCharge

        if chargeDelta > 0 {
            let totalAvailable = policy.ceiling(dimension, perOwner: false) - totals[dimension, default: 0]
            let ownerAvailable = policy.ceiling(dimension, perOwner: true)
                - owners[owner, default: [:]][dimension, default: 0]
            guard chargeDelta <= totalAvailable, chargeDelta <= ownerAvailable else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "The resource budget is currently full."
                )
            }
        }

        entry.statePayloadBytes  = toBytes
        entry.charges[dimension] = desiredCharge
        entries[reservationID]   = entry
        totals[dimension, default: 0] += chargeDelta
        owners[owner, default: [:]][dimension, default: 0] += chargeDelta
        return true
    }

    /// resizeMemoryReservation changes one ordinary temporary-memory reservation in place.
    /// It exists for host-owned retained buffers whose lifetime outlives one callback.
    func resizeMemoryReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        fromBytes      : Int,
        toBytes        : Int
    ) throws -> Bool {
        guard var entry = entries[reservationID] else { return false }
        guard entry.reservation.owner == owner else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "The reservation belongs to another addon."
            )
        }
        guard entry.memoryPayloadBytes == fromBytes else { return false }

        let desired   = try policy.charges(for: .temporaryMemory(bytes: toBytes))
        let dimension = ResourceDimension.admittedMemoryBytes
        let delta     = desired[dimension, default: 0] - entry.charges[dimension, default: 0]
        if delta > 0 {
            guard delta <= policy.ceiling(dimension, perOwner: false) - totals[dimension, default: 0],
                  delta <= policy.ceiling(dimension, perOwner: true)
                    - owners[owner, default: [:]][dimension, default: 0]
            else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "The resource budget is currently full."
                )
            }
        }

        entry.memoryPayloadBytes = toBytes
        entry.charges[dimension] = desired[dimension]
        entries[reservationID]   = entry
        totals[dimension, default: 0] += delta
        owners[owner, default: [:]][dimension, default: 0] += delta
        return true
    }

    /// resizeDiskReservation atomically resizes one disk pool, preserving its class and metadata.
    /// Expected size detects stale accounting; callers still own operation authority and serialization.
    func resizeDiskReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        fromBytes      : Int,
        toBytes        : Int
    ) throws -> Bool {
        guard var entry = entries[reservationID] else { return false }
        guard entry.reservation.owner == owner else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "The reservation belongs to another addon."
            )
        }
        guard entry.observedDiskSecret == nil else { return false }

        let dimension     : ResourceDimension
        let desiredRequest: ResourceRequest
        if entry.charges[.diskStateBytes] != nil {
            dimension      = .diskStateBytes
            desiredRequest = .diskState(bytes: toBytes)
        } else if entry.charges[.diskCacheBytes] != nil {
            dimension      = .diskCacheBytes
            desiredRequest = .diskCache(bytes: toBytes)
        } else {
            return false
        }
        guard entry.charges[dimension] == fromBytes else { return false }

        let desiredCharges = try policy.charges(for: desiredRequest)
        if toBytes > fromBytes {
            try requireDiskGrowthEligibility(owner: owner)
        }

        for affected in [dimension, .diskBytes] {
            let delta = desiredCharges[affected, default: 0] - entry.charges[affected, default: 0]
            if delta > 0 {
                guard delta <= policy.ceiling(affected, perOwner: false) - totals[affected, default: 0],
                      delta <= policy.ceiling(affected, perOwner: true)
                        - owners[owner, default: [:]][affected, default: 0]
                else {
                    throw AddonFailure(
                        code  : .resourceDenied,
                        reason: "The resource budget is currently full."
                    )
                }
            }
        }

        for affected in [dimension, .diskBytes] {
            let delta               = desiredCharges[affected, default: 0] - entry.charges[affected, default: 0]
            entry.charges[affected] = desiredCharges[affected]
            totals[affected, default: 0] += delta
            owners[owner, default: [:]][affected, default: 0] += delta
        }
        entries[reservationID] = entry
        return true
    }

    public func release(
        _ reservationID: UUID,
        owner          : AddonID
    ) throws {
        guard let entry = entries[reservationID] else { return }
        guard entry.reservation.owner == owner else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "The reservation belongs to another addon."
            )
        }
        guard entry.retainedAssetSecret == nil else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "A live raster backing can only be released by its final disposal."
            )
        }
        guard entry.observedDiskSecret == nil else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Observed disk accounting requires measured zero before final release."
            )
        }

        releaseCanonical(reservationID)
    }

    private func releaseCanonical(_ reservationID: UUID) {
        guard let entry = entries.removeValue(forKey: reservationID) else { return }

        let owner = entry.reservation.owner
        for (dimension, amount) in entry.charges {
            totals[dimension, default: 0] -= amount
            owners[owner, default: [:]][dimension, default: 0] -= amount
        }
        if owners[owner]?.values.allSatisfy({ $0 == 0 }) == true { owners.removeValue(forKey: owner) }
    }

    public func releaseAll(owner: AddonID) {
        for id in entries.keys.filter({
            entries[$0]?.reservation.owner == owner
                && entries[$0]?.retainedAssetSecret == nil
                && entries[$0]?.observedDiskSecret == nil
        }) {
            releaseCanonical(id)
        }
    }

    public func withReservation<Result: Sendable>(
        _ request: ResourceRequest,
        owner    : AddonID,
        operation: @Sendable (ResourceReservation) async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        let reservation = try admit(request, owner: owner)
        defer { releaseCanonical(reservation.id) }
        return try await operation(reservation)
    }

    public func usage(
        _ dimension: ResourceDimension,
        owner      : AddonID? = nil
    ) -> Int {
        if let owner { return owners[owner]?[dimension] ?? 0 }
        return totals[dimension, default: 0]
    }
}

/// RetainedAssetToken is the opaque module-internal disposal authority. Only this file can mint
/// a token; the backing wrapper and renderer never receive it. An exact stale token is
/// idempotent, but it cannot complete a different entry or a different governor. The governor
/// identity is a lifetime nonce, not a recyclable object address.
struct RetainedAssetToken: Sendable {

    let reservation: ResourceReservation

    fileprivate let governor: UUID
    fileprivate let secret  : UUID

    fileprivate init(
        reservation: ResourceReservation,
        governor   : UUID,
        secret     : UUID
    ) {
        self.reservation = reservation
        self.governor    = governor
        self.secret      = secret
    }
}

extension ResourceGovernor {

    static let retainedAssetSlotCharge = 4_096

    /// withAssetDecodeReservation protects staging bytes from owner cleanup while native work runs.
    /// The operation must return only after releasing temporary buffers. Its scoped secret uses
    /// the same protected-entry exclusion as retained rasters; no release capability escapes.
    func withAssetDecodeReservation<Result: Sendable>(
        bytes    : Int,
        owner    : AddonID,
        operation: @Sendable () async throws -> Result
    ) async throws -> Result {
        try Task.checkCancellation()
        let charges     = try policy.charges(for: .temporaryMemory(bytes: bytes))
        let reservation = try insert(
            reservation        : ResourceReservation(id: UUID(), owner: owner),
            charges            : charges,
            statePayloadBytes  : nil,
            retainedAssetSecret: UUID()
        )
        defer { releaseCanonical(reservation.id) }
        return try await operation()
    }

    func admitRetainedAsset(
        bytes: Int,
        owner: AddonID
    ) throws -> RetainedAssetToken {
        var charges = try policy.charges(for: .asset(bytes: bytes))
        // .asset has validated bytes before either bounded addition.
        charges[.retainedStateBytes, default: 0] += Self.retainedAssetSlotCharge
        charges[.admittedMemoryBytes, default: 0] += Self.retainedAssetSlotCharge

        let secret      = UUID()
        let reservation = try insert(
            reservation        : ResourceReservation(id: UUID(), owner: owner),
            charges            : charges,
            statePayloadBytes  : nil,
            retainedAssetSecret: secret
        )
        return RetainedAssetToken(
            reservation: reservation,
            governor   : retainedAssetLifetime,
            secret     : secret
        )
    }

    func completeRetainedAsset(
        _ token: RetainedAssetToken,
        owner  : AddonID
    ) throws {
        guard token.reservation.owner == owner, token.governor == retainedAssetLifetime else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "The raster disposal authority does not match."
            )
        }
        guard let entry = entries[token.reservation.id] else { return }
        guard entry.reservation.owner == owner, entry.retainedAssetSecret == token.secret else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "The raster disposal lifetime does not match."
            )
        }

        releaseCanonical(token.reservation.id)
    }
}

/// ObservedDiskToken grants one protected lifetime authority to reconcile measured disk bytes.
/// Its reservation identifier is observable bookkeeping, not generic release authority.
struct ObservedDiskToken: Sendable {

    let reservation: ResourceReservation

    fileprivate let governor: UUID
    fileprivate let secret  : UUID

    fileprivate init(
        reservation: ResourceReservation,
        governor   : UUID,
        secret     : UUID
    ) {
        self.reservation = reservation
        self.governor    = governor
        self.secret      = secret
    }
}

extension ResourceGovernor {

    /// admitObservedDisk prepays one protected data ledger with strict initial disk admission.
    /// Zero bytes requests only metadata, allowing existing files to be discovered while
    /// other ledgers are overbudget. It does not authorize a framework write or disk growth.
    /// Optional retained metadata consumes both state and admitted memory until final release;
    /// its entry has no generic state-resize authority, so owner cleanup cannot erase it.
    func admitObservedDisk(
        bytes                : Int,
        owner                : AddonID,
        retainedMetadataBytes: Int = 0
    ) throws -> ObservedDiskToken {
        var charges                  = try policy.charges(for: .diskState(bytes: bytes))
        let metadataCharges          = try policy.charges(for: .state(bytes: retainedMetadataBytes))
        charges[.retainedStateBytes] = metadataCharges[.retainedStateBytes]
        if retainedMetadataBytes > 0 {
            charges[.admittedMemoryBytes] = retainedMetadataBytes
        }

        let secret      = UUID()
        let reservation = try insert(
            reservation        : ResourceReservation(id: UUID(), owner: owner),
            charges            : charges,
            statePayloadBytes  : nil,
            retainedAssetSecret: nil,
            observedDiskSecret : secret
        )
        return ObservedDiskToken(
            reservation: reservation,
            governor   : observedDiskLifetime,
            secret     : secret
        )
    }

    /// growObservedDisk strictly prepays additional capacity while retaining token identity.
    /// Only measured reconciliation may shrink a ledger. A stale expected size returns false.
    func growObservedDisk(
        _ token  : ObservedDiskToken,
        owner    : AddonID,
        fromBytes: Int,
        toBytes  : Int
    ) throws -> Bool {
        let entry = try observedDiskEntry(token, owner: owner)
        guard fromBytes >= 0, toBytes >= fromBytes else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Observed disk growth requires nonnegative, nondecreasing sizes."
            )
        }
        guard entry.charges[.diskStateBytes] == fromBytes else { return false }

        _         = try policy.charges(for: .diskState(bytes: toBytes))
        let delta = toBytes - fromBytes
        if delta > 0 {
            try requireDiskGrowthEligibility(owner: owner)
            for dimension in [ResourceDimension.diskStateBytes, .diskBytes] {
                guard delta <= policy.ceiling(dimension, perOwner: false) - totals[dimension, default: 0],
                      delta <= policy.ceiling(dimension, perOwner: true)
                        - owners[owner, default: [:]][dimension, default: 0]
                else {
                    throw AddonFailure(
                        code  : .resourceDenied,
                        reason: "The resource budget is currently full."
                    )
                }
            }
        }

        return try reconcileObservedDisk(
            token,
            owner        : owner,
            fromBytes    : fromBytes,
            measuredBytes: toBytes
        )
    }

    /// reconcileObservedDisk records actual retained bytes even beyond policy ceilings.
    /// It checks both owner/global totals for arithmetic overflow before any mutation.
    /// A size match is accounting CAS, not caller epoch authorization or proof of a file scan.
    func reconcileObservedDisk(
        _ token      : ObservedDiskToken,
        owner        : AddonID,
        fromBytes    : Int,
        measuredBytes: Int
    ) throws -> Bool {
        var entry = try observedDiskEntry(token, owner: owner)
        guard fromBytes >= 0, measuredBytes >= 0 else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Observed disk sizes must be nonnegative."
            )
        }
        guard entry.charges[.diskStateBytes] == fromBytes else { return false }

        let delta = measuredBytes - fromBytes
        for dimension in [ResourceDimension.diskStateBytes, .diskBytes] {
            let total      = totals[dimension, default: 0].addingReportingOverflow(delta)
            let ownerTotal = owners[owner, default: [:]][dimension, default: 0].addingReportingOverflow(delta)
            guard !total.overflow,
                  !ownerTotal.overflow,
                  total.partialValue >= 0,
                  ownerTotal.partialValue >= 0
            else {
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "Observed disk accounting exceeds its integer representation."
                )
            }
        }

        for dimension in [ResourceDimension.diskStateBytes, .diskBytes] {
            entry.charges[dimension] = measuredBytes
            totals[dimension, default: 0] += delta
            owners[owner, default: [:]][dimension, default: 0] += delta
        }
        entries[token.reservation.id] = entry
        return true
    }

    /// observedDiskStatus samples the current owner/global debt including unrelated ledgers.
    func observedDiskStatus(
        _ token: ObservedDiskToken,
        owner  : AddonID
    ) throws -> ObservedDiskStatus {
        let entry         = try observedDiskEntry(token, owner: owner)
        let ownerOverage  = diskOverage(owner: owner)
        let globalOverage = diskOverage(owner: nil)

        return ObservedDiskStatus(
            bytes             : entry.charges[.diskStateBytes, default: 0],
            ownerOverageBytes : ownerOverage,
            globalOverageBytes: globalOverage,
            permitsWrites     : ownerOverage == 0 && globalOverage == 0
        )
    }

    /// completeObservedDisk releases metadata only after canonical measured disk reaches zero.
    /// Completed, foreign and wrong-owner capabilities cannot affect a later lifetime.
    func completeObservedDisk(
        _ token: ObservedDiskToken,
        owner  : AddonID
    ) throws {
        let entry = try observedDiskEntry(token, owner: owner)
        guard entry.charges[.diskStateBytes] == 0 else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Observed disk accounting requires measured zero before final release."
            )
        }

        releaseCanonical(token.reservation.id)
    }

    /// observedDiskEntry validates the exact owner, governor and protected lifetime before access.
    private func observedDiskEntry(
        _ token: ObservedDiskToken,
        owner  : AddonID
    ) throws -> Entry {
        guard token.governor == observedDiskLifetime,
              token.reservation.owner == owner,
              let entry = entries[token.reservation.id],
              entry.reservation.owner == owner,
              entry.observedDiskSecret == token.secret
        else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "The observed disk authority does not match a live ledger."
            )
        }

        return entry
    }

    /// diskOverage checks overlapping data/cache/combined dimensions without adding them twice.
    private func diskOverage(owner: AddonID?) -> Int {
        var overage = 0
        for dimension in [ResourceDimension.diskStateBytes, .diskCacheBytes, .diskBytes] {
            let charged = usage(dimension, owner: owner)
            let ceiling = policy.ceiling(dimension, perOwner: owner != nil)
            if charged > ceiling {
                overage = max(overage, charged - ceiling)
            }
        }

        return overage
    }

    /// requireDiskGrowthEligibility prevents ordinary disk pools from bypassing observed debt.
    /// A different owner's local debt does not block growth unless a global ceiling is exceeded.
    private func requireDiskGrowthEligibility(owner: AddonID) throws {
        guard diskOverage(owner: owner) == 0, diskOverage(owner: nil) == 0 else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Measured disk usage exceeds an owner or global budget."
            )
        }
    }
}

/// AssetTransferReservationToken grants disposal of exactly one compressed-input lifetime.
/// Its distinct type cannot complete raster/decode tokens, although entries reuse protection.
struct AssetTransferReservationToken: Sendable {

    let reservation: ResourceReservation

    fileprivate let governor: UUID
    fileprivate let secret  : UUID

    fileprivate init(
        reservation: ResourceReservation,
        governor   : UUID,
        secret     : UUID
    ) {
        self.reservation = reservation
        self.governor    = governor
        self.secret      = secret
    }
}

extension ResourceGovernor {

    /// admitAssetTransfer prepays a fixed buffer and its controlled COW/snapshot overlap.
    /// The 4,096-byte control allowance is separate from the policy's 1,024-byte entry.
    func admitAssetTransfer(
        bytes: Int,
        owner: AddonID
    ) throws -> AssetTransferReservationToken {
        try Task.checkCancellation()
        guard (1...1_048_576).contains(bytes) else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "Invalid compressed asset length."
            )
        }

        let charges     = try policy.charges(for: .temporaryMemory(bytes: 2 * bytes + 4_096))
        let secret      = UUID()
        let reservation = try insert(
            reservation        : ResourceReservation(id: UUID(), owner: owner),
            charges            : charges,
            statePayloadBytes  : nil,
            retainedAssetSecret: secret
        )
        return AssetTransferReservationToken(
            reservation: reservation,
            governor   : retainedAssetLifetime,
            secret     : secret
        )
    }

    /// completeAssetTransfer is idempotent only for this exact owner and governor lifetime.
    func completeAssetTransfer(
        _ token: AssetTransferReservationToken,
        owner  : AddonID
    ) throws {
        guard token.reservation.owner == owner, token.governor == retainedAssetLifetime else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "The transfer disposal authority does not match."
            )
        }
        guard let entry = entries[token.reservation.id] else { return }
        guard entry.reservation.owner == owner, entry.retainedAssetSecret == token.secret else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "The transfer disposal lifetime does not match."
            )
        }
#if DEBUG
        if assetTransferRefundAttempts < UInt64.max { assetTransferRefundAttempts += 1 }
        lastAssetTransferRefund = token.reservation.id
        if assetTransferRefundFailures > 0 {
            assetTransferRefundFailures -= 1
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "Injected asset transfer refund failure."
            )
        }
#endif
        releaseCanonical(token.reservation.id)
#if DEBUG
        if assetTransferRefundSuccesses < UInt64.max { assetTransferRefundSuccesses += 1 }
#endif
    }

#if DEBUG
    struct AssetTransferRefundSnapshot: Sendable {

        let attempts         : UInt64
        let successes        : UInt64
        let lastReservationID: UUID?
        let present          : Bool
        let memoryBytes      : Int
    }

    /// assetTransferRefundSnapshotForTesting observes canonical entries without exposing
    /// their protected disposal secrets or retaining a historical per-token table.
    func assetTransferRefundSnapshotForTesting(_ id: UUID) -> AssetTransferRefundSnapshot {
        AssetTransferRefundSnapshot(
            attempts         : assetTransferRefundAttempts,
            successes        : assetTransferRefundSuccesses,
            lastReservationID: lastAssetTransferRefund,
            present          : entries[id] != nil,
            memoryBytes      : entries[id]?.charges[.admittedMemoryBytes] ?? 0
        )
    }

    /// armAssetTransferRefundFailureForTesting injects the requested number of protected-refund
    /// failures so a test can prove the exact reservation token survives a failed disposal.
    func armAssetTransferRefundFailureForTesting(count: Int = 1) {
        assetTransferRefundFailures = max(0, count)
    }
#endif
}
