//
//  AddonHealthStore.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AddonVersionIdentity names the verified publisher, addon, and semantic version
/// whose health history the host retains. The publisher is verifier output rather
/// than addon payload authentication; build metadata cannot create a fresh health
/// identity because `SemanticVersion` intentionally compares version precedence.
public struct AddonVersionIdentity: Hashable, Sendable {
    public let verifiedIdentity: VerifiedAddonIdentity
    public let version: SemanticVersion

    public init(
        verifiedIdentity : VerifiedAddonIdentity,
        version          : SemanticVersion
    ) throws {
        let publisherBytes = verifiedIdentity.publisher.utf8.count
        let prereleaseBytes = version.prerelease?.utf8.count ?? 0
        let buildBytes      = version.buildMetadata?.utf8.count ?? 0
        let reparsedVersion = SemanticVersion(version.description)
        guard publisherBytes > 0, publisherBytes <= 512,
              !verifiedIdentity.publisher.allSatisfy(\.isWhitespace),
              version.major >= 0, version.minor >= 0, version.patch >= 0,
              prereleaseBytes <= 128, buildBytes <= 128,
              reparsedVersion?.major == version.major,
              reparsedVersion?.minor == version.minor,
              reparsedVersion?.patch == version.patch,
              reparsedVersion?.prerelease == version.prerelease,
              reparsedVersion?.buildMetadata == version.buildMetadata else {
            throw AddonFailure(
                code   : .invalidPayload,
                reason : "The verified addon version identity is invalid."
            )
        }
        self.verifiedIdentity = verifiedIdentity
        self.version = version
    }
}

/// AddonHealthSession binds health events to one host-issued connection and an
/// unguessable health token. Callers can retain the value, but only `bind` creates
/// one that the store recognizes as current.
public struct AddonHealthSession: Hashable, Sendable {
    public let version: AddonVersionIdentity
    public let generation: ConnectionGeneration
    public let token: UUID

    fileprivate init(
        version    : AddonVersionIdentity,
        generation : ConnectionGeneration,
        token      : UUID
    ) {
        self.version = version
        self.generation = generation
        self.token = token
    }
}

/// AddonRetryTicket is the one-shot authorization associated with an absolute
/// monotonic deadline. The ticket remains tied to the failed session generation;
/// binding a replacement session or cancelling the owner invalidates it.
public struct AddonRetryTicket: Equatable, Sendable {
    public let version: AddonVersionIdentity
    public let failedGeneration: ConnectionGeneration
    public let deadline: Duration
    public let token: UUID

    fileprivate init(
        version          : AddonVersionIdentity,
        failedGeneration : ConnectionGeneration,
        deadline         : Duration,
        token            : UUID
    ) {
        self.version = version
        self.failedGeneration = failedGeneration
        self.deadline = deadline
        self.token = token
    }
}

/// AddonHealthDecision tells the runtime whether the current process may remain,
/// must stop, is quarantined, or has one crash retry for the common deadline queue.
public enum AddonHealthDecision: Equatable, Sendable {
    case keep
    case stop
    case quarantine
    case retryAt(AddonRetryTicket)
}

/// AddonHealthViolation classifies already-established host observations. This
/// state machine does not read process metrics or terminate a native process.
public enum AddonHealthViolation: Sendable {
    case moderate
    case severe
}

/// AddonHealthSnapshot exposes bounded diagnostic state without exposing mutable
/// policy or the store's host-issued session and retry credentials.
public struct AddonHealthSnapshot: Equatable, Sendable {
    public let isQuarantined: Bool
    public let moderateIncidentCount: Int
    public let crashRetryCount: Int
    public let hasPendingRetry: Bool
}

/// AddonHealthStore retains bounded health state per verified addon version.
/// It owns no tasks, timers, metric readers, or launcher operations. All elapsed
/// intervals use the monotonic half of `RuntimeInstant`; the wall date is checked
/// only to reject malformed clock samples shared with the rest of the runtime.
public struct AddonHealthStore: Sendable {
    private struct Record: Sendable {
        let identity: AddonVersionIdentity
        let charge: Int
        var moderateIncidents: [Duration] = []
        var crashRetryCount = 0
        var pendingRetry: AddonRetryTicket?
        var lastAcceptedInstant: Duration?
        var isQuarantined = false
    }

    // These charges conservatively cover dictionary buckets, version identity,
    // two incident instants, retry state, and value-semantic copy-on-write storage.
    private static let maximumHostRecords = 1_024
    private static let maximumHostBytes   = 8 * 1_024 * 1_024
    private static let recordBaseCharge   = 2_048
    private static let accountBaseCharge  = 512
    private static let moderateWindow     = Duration.seconds(300)
    private static let retryDelays        = [
        Duration.seconds(1),
        Duration.seconds(5),
        Duration.seconds(30),
    ]

    private let maximumRecords: Int
    private let maximumRetainedBytes: Int
    private var records: [AddonVersionIdentity: Record] = [:]
    private var activeSessions: [AddonID: AddonHealthSession] = [:]
    public private(set) var retainedBytes = 0
    public var count: Int { records.count }

    public init(
        maximumRecords       : Int = 1_024,
        maximumRetainedBytes : Int = 8 * 1_024 * 1_024
    ) {
        self.maximumRecords = min(Self.maximumHostRecords, max(0, maximumRecords))
        self.maximumRetainedBytes = min(
            Self.maximumHostBytes,
            max(0, maximumRetainedBytes)
        )
    }

    /// register admits one durable version record or returns the existing state.
    /// Existing records are never refreshed, evicted, or cleared by registration.
    public mutating func register(
        _ identity: AddonVersionIdentity
    ) throws -> AddonHealthSnapshot {
        if let existing = records[identity] {
            return snapshot(existing)
        }
        let charge = recordCharge(identity)
        guard records.count < maximumRecords,
              charge <= maximumRetainedBytes - retainedBytes else {
            throw AddonFailure(
                code   : .resourceDenied,
                reason : "The addon health history budget is exhausted."
            )
        }
        records[identity] = Record(identity: identity, charge: charge)
        retainedBytes += charge
        return snapshot(for: identity) ?? AddonHealthSnapshot(
            isQuarantined        : false,
            moderateIncidentCount: 0,
            crashRetryCount      : 0,
            hasPendingRetry      : false
        )
    }

    /// bind replaces the current host session for this addon ID. Replacement
    /// invalidates every pending retry for the addon before accepting new events.
    public mutating func bind(
        _ identity : AddonVersionIdentity,
        generation : ConnectionGeneration
    ) throws -> AddonHealthSession {
        guard let record = records[identity] else {
            throw AddonFailure(
                code   : .dependencyUnavailable,
                reason : "The addon version has no admitted health record."
            )
        }
        guard !record.isQuarantined else {
            throw AddonFailure(
                code   : .resourceDenied,
                reason : "The addon version is quarantined pending host administration."
            )
        }
        let owner = identity.verifiedIdentity.addonID
        if activeSessions[owner] == nil {
            let charge = accountCharge(owner)
            guard charge <= maximumRetainedBytes - retainedBytes else {
                throw AddonFailure(
                    code   : .resourceDenied,
                    reason : "The addon health account index budget is exhausted."
                )
            }
            retainedBytes += charge
        }
        cancelPendingRetries(owner: owner)
        let session = AddonHealthSession(
            version    : identity,
            generation : generation,
            token      : UUID()
        )
        activeSessions[owner] = session
        return session
    }

    /// record applies a host-classified resource violation to the current session.
    /// The five-minute window is closed at its boundary: an incident exactly 300
    /// seconds old still counts. Only the two incidents needed before quarantine
    /// are retained, so repeated observations cannot form an event log.
    public mutating func record(
        _ violation : AddonHealthViolation,
        from session: AddonHealthSession,
        at instant  : RuntimeInstant
    ) throws -> AddonHealthDecision? {
        try validate(instant)
        guard isCurrent(session), var record = records[session.version] else {
            return nil
        }
        try validateOrder(instant.monotonic, after: record.lastAcceptedInstant)
        record.lastAcceptedInstant = instant.monotonic

        switch violation {
        case .moderate:
            let decision = applyModerate(to: &record, at: instant.monotonic)
            records[session.version] = record
            if decision == .quarantine {
                removeActiveSession(owner: session.version.verifiedIdentity.addonID)
            }
            return decision
        case .severe:
            record.pendingRetry = nil
            records[session.version] = record
            removeActiveSession(owner: session.version.verifiedIdentity.addonID)
            return .stop
        }
    }

    /// recordModerateDuringRetry records a moderate CPU incident against a processless owner, which
    /// retains delegated CPU health while its exact crash ticket blocks binding. This preserves the
    /// retry on keep and never treats a stale ticket as authority over another generation.
    mutating func recordModerateDuringRetry(
        from retry: AddonRetryTicket,
        at instant: RuntimeInstant
    ) throws -> AddonHealthDecision? {
        try validate(instant)
        let owner = retry.version.verifiedIdentity.addonID
        guard activeSessions[owner] == nil,
              var record = records[retry.version],
              record.pendingRetry == retry,
              !record.isQuarantined else { return nil }
        try validateOrder(instant.monotonic, after: record.lastAcceptedInstant)
        record.lastAcceptedInstant = instant.monotonic
        let decision = applyModerate(to: &record, at: instant.monotonic)
        records[retry.version] = record
        return decision
    }

    private func applyModerate(
        to record: inout Record,
        at instant: Duration
    ) -> AddonHealthDecision {
        record.moderateIncidents.removeAll { incident in
            instant - incident > Self.moderateWindow
        }
        if record.moderateIncidents.count == 2 {
            record.moderateIncidents.removeAll(keepingCapacity: true)
            record.isQuarantined = true
            record.pendingRetry = nil
            return .quarantine
        }
        record.moderateIncidents.append(instant)
        return .keep
    }

    /// crashed closes the failed session and, while demand exists, issues the next
    /// 1/5/30-second retry. A fourth demanded crash quarantines the version.
    public mutating func crashed(
        _ session     : AddonHealthSession,
        demandExists : Bool,
        at instant    : RuntimeInstant
    ) throws -> AddonHealthDecision? {
        try validate(instant)
        guard isCurrent(session), var record = records[session.version] else {
            return nil
        }
        try validateOrder(instant.monotonic, after: record.lastAcceptedInstant)
        record.lastAcceptedInstant = instant.monotonic
        record.pendingRetry = nil
        removeActiveSession(owner: session.version.verifiedIdentity.addonID)

        guard demandExists else {
            records[session.version] = record
            return .stop
        }
        guard record.crashRetryCount < Self.retryDelays.count else {
            record.isQuarantined = true
            records[session.version] = record
            return .quarantine
        }
        let delay = Self.retryDelays[record.crashRetryCount]
        record.crashRetryCount += 1
        let retry = AddonRetryTicket(
            version          : session.version,
            failedGeneration : session.generation,
            deadline         : instant.monotonic + delay,
            token            : UUID()
        )
        record.pendingRetry = retry
        records[session.version] = record
        return .retryAt(retry)
    }

    /// consume authorizes one due retry only while the addon is enabled and still
    /// demanded. A due attempt is consumed before the checks, making late duplicate
    /// callbacks harmless. Early delivery leaves the deadline available to rearm.
    public mutating func consume(
        _ retry      : AddonRetryTicket,
        demandExists: Bool,
        isEnabled   : Bool,
        at instant  : RuntimeInstant
    ) throws -> Bool {
        try validate(instant)
        guard var record = records[retry.version],
              record.pendingRetry == retry,
              instant.monotonic >= retry.deadline else {
            return false
        }
        try validateOrder(instant.monotonic, after: record.lastAcceptedInstant)
        record.lastAcceptedInstant = instant.monotonic
        record.pendingRetry = nil
        records[retry.version] = record
        let owner = retry.version.verifiedIdentity.addonID
        guard demandExists, isEnabled, !record.isQuarantined,
              activeSessions[owner] == nil else {
            return false
        }
        return true
    }

    /// cancel invalidates current sessions and retry tickets for disable, removal,
    /// or permission revocation. Durable incident and quarantine history remains.
    public mutating func cancel(owner: AddonID) {
        removeActiveSession(owner: owner)
        cancelPendingRetries(owner: owner)
    }

    /// administrativelyReset is the deliberate host-only path that clears health
    /// history for an admitted version. It also requires a fresh session binding.
    @discardableResult
    public mutating func administrativelyReset(
        _ identity: AddonVersionIdentity
    ) -> Bool {
        guard var record = records[identity] else { return false }
        let owner = identity.verifiedIdentity.addonID
        if activeSessions[owner]?.version == identity {
            removeActiveSession(owner: owner)
        }
        record.moderateIncidents.removeAll(keepingCapacity: true)
        record.crashRetryCount = 0
        record.pendingRetry = nil
        record.lastAcceptedInstant = nil
        record.isQuarantined = false
        records[identity] = record
        return true
    }

    /// administrativelyRemove deliberately releases a version tombstone. Runtime
    /// registration and normal provider restarts never call this eviction path.
    @discardableResult
    public mutating func administrativelyRemove(
        _ identity: AddonVersionIdentity
    ) -> Bool {
        guard let record = records.removeValue(forKey: identity) else { return false }
        if activeSessions[identity.verifiedIdentity.addonID]?.version == identity {
            removeActiveSession(owner: identity.verifiedIdentity.addonID)
        }
        retainedBytes -= record.charge
        return true
    }

    public func snapshot(
        for identity: AddonVersionIdentity
    ) -> AddonHealthSnapshot? {
        records[identity].map(snapshot)
    }

    /// nextDeadline returns the earliest absolute elapsed retry deadline for the
    /// common host `DeadlineQueue`; this store never schedules its own wakeup.
    public var nextDeadline: Duration? {
        var earliest: Duration?
        for record in records.values {
            guard let deadline = record.pendingRetry?.deadline else { continue }
            earliest = earliest.map { min($0, deadline) } ?? deadline
        }
        return earliest
    }

    /// pendingRetryTickets projects the bounded canonical retry state for a host
    /// wake. Consumption remains the authority that validates due time and demand.
    var pendingRetryTickets: [AddonRetryTicket] {
        records.values.compactMap(\.pendingRetry).sorted {
            if $0.deadline != $1.deadline { return $0.deadline < $1.deadline }
            let left = $0.version.verifiedIdentity
            let right = $1.version.verifiedIdentity
            if left.addonID != right.addonID { return left.addonID.rawValue < right.addonID.rawValue }
            if left.publisher != right.publisher { return left.publisher < right.publisher }
            return $0.version.version.description < $1.version.version.description
        }
    }

    /// cancelPendingRetries invalidates retry tickets without changing live
    /// sessions or durable health history.
    mutating func cancelPendingRetries() {
        for identity in Array(records.keys) {
            guard var record = records[identity], record.pendingRetry != nil else { continue }
            record.pendingRetry = nil
            records[identity] = record
        }
    }

    private func snapshot(_ record: Record) -> AddonHealthSnapshot {
        AddonHealthSnapshot(
            isQuarantined         : record.isQuarantined,
            moderateIncidentCount : record.moderateIncidents.count,
            crashRetryCount       : record.crashRetryCount,
            hasPendingRetry       : record.pendingRetry != nil
        )
    }

    private func isCurrent(_ session: AddonHealthSession) -> Bool {
        activeSessions[session.version.verifiedIdentity.addonID] == session
    }

    private func recordCharge(_ identity: AddonVersionIdentity) -> Int {
        Self.recordBaseCharge
            + identity.verifiedIdentity.publisher.utf8.count
            + identity.verifiedIdentity.addonID.rawValue.utf8.count
            + identity.version.description.utf8.count
    }

    private func accountCharge(_ owner: AddonID) -> Int {
        Self.accountBaseCharge + owner.rawValue.utf8.count
    }

    private mutating func removeActiveSession(owner: AddonID) {
        guard activeSessions.removeValue(forKey: owner) != nil else { return }
        retainedBytes -= accountCharge(owner)
    }

    private mutating func cancelPendingRetries(owner: AddonID) {
        for identity in Array(records.keys) where identity.verifiedIdentity.addonID == owner {
            guard var record = records[identity], record.pendingRetry != nil else { continue }
            record.pendingRetry = nil
            records[identity] = record
        }
    }

    private func validate(_ instant: RuntimeInstant) throws {
        guard instant.wall.timeIntervalSince1970.isFinite,
              instant.monotonic >= .zero else {
            throw AddonFailure(
                code   : .invalidPayload,
                reason : "The runtime clock is invalid."
            )
        }
    }

    private func validateOrder(
        _ instant : Duration,
        after last: Duration?
    ) throws {
        guard last.map({ instant >= $0 }) ?? true else {
            throw AddonFailure(
                code   : .invalidPayload,
                reason : "Health events must use nondecreasing monotonic time."
            )
        }
    }
}
