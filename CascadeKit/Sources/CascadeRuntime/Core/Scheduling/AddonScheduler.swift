//
//  AddonScheduler.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AddonScheduler admits finite work independently from process and publication
/// lifetimes. A runtime actor owns this value; takeReady returns a ticket, never
/// executes provider code. Completion releases admission only after the runtime
/// observes that the work or its process has actually ended.
public struct AddonScheduler: Sendable {

    public enum Work: Equatable, Sendable {

        case command(ActionRequest)
        case refresh(PublicationID)
    }

    public enum Phase: Equatable, Sendable {

        case queued
        case running
        case stopping
    }

    public struct Job: Equatable, Sendable {

        public let id      : UUID
        public let owner   : AddonID
        public let work    : Work
        public let deadline: Duration
        public let phase   : Phase
    }

    public struct Cancellation: Equatable, Sendable {

        public let job         : Job
        public let requiresStop: Bool
    }

    private struct Record {

        let owner     : AddonID
        let work      : Work
        let enqueuedAt: Duration
        let sequence  : UInt64
        var deadline  : Duration
        var phase     : Phase

        func job(id: UUID) -> Job {
            Job(
                id      : id,
                owner   : owner,
                work    : work,
                deadline: deadline,
                phase   : phase
            )
        }
    }

    // Each entry includes a possible 4 KiB command input, bounded identities and
    // dictionary overhead. No capacity is preallocated for installed-but-idle addons.
    static let recordCharge = 8_192

    private let maximumRetainedBytes: Int
    private var records             : [UUID: Record] = [:]
    private var busyOwners          : Set<AddonID> = []
    private var sequence            : UInt64 = 0

    public var count        : Int { records.count }
    public var retainedBytes: Int { count * Self.recordCharge }
    public var runningCount : Int { busyOwners.count }

    public init(maximumRetainedBytes: Int = 8 * 1_024 * 1_024) {
        self.maximumRetainedBytes = min(8 * 1_024 * 1_024, max(0, maximumRetainedBytes))
    }

    /// enqueue preserves command identities and coalesces only waiting refreshes.
    /// A refresh arriving during execution creates one follow-up, not another job
    /// running concurrently. The journal supplies command deadlines already anchored
    /// at admission; this boundary can only shorten them.
    public mutating func enqueue(
        _ work    : Work,
        owner     : AddonID,
        deadline  : Duration,
        at instant: RuntimeInstant
    ) throws -> UUID {
        guard instant.wall.timeIntervalSince1970.isFinite,
              instant.monotonic >= .zero,
              deadline > instant.monotonic
        else {
            throw AddonFailure(
                code  : .deadlineExceeded,
                reason: "The job has no valid remaining time."
            )
        }

        let admittedDeadline = min(deadline, instant.monotonic + .seconds(30))
        switch work {
            case .command(let request):
                try request.validate()
                try request.publicationID.validateOwner(owner)

            // The journal already converted the request's civil deadline at
            // admission. A later clock adjustment cannot reinterpret that promise.
            case .refresh(let publication): try publication.validateOwner(owner)
        }

        var pendingCommands  = 0
        var pendingRefreshes = 0
        // The global byte ceiling bounds this event-only scan to at most 1,024
        // entries. Avoid secondary maps retaining owner/publication keys after stop.
        for (id, record) in records where record.owner == owner {
            switch (record.work, work) {
                case (.command(let existing), .command(let request)) where existing.requestID == request.requestID:
                    guard existing == request else {
                        throw AddonFailure(
                            code  : .invalidPayload,
                            reason: "A command ID cannot be reused with changed input."
                        )
                    }
                    return id

                case (.refresh(let existing), .refresh(let publication))
                        where existing == publication && record.phase == .queued:
                    var updated      = record
                    updated.deadline = min(record.deadline, admittedDeadline)
                    records[id]      = updated
                    return id

                default: break
            }
            guard record.phase == .queued else { continue }

            switch record.work {
                case .command: pendingCommands += 1
                case .refresh: pendingRefreshes += 1
            }
        }

        switch work {
            case .command where pendingCommands >= 4:
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "The addon command queue is full."
                )

            case .refresh where pendingRefreshes >= 16:
                throw AddonFailure(
                    code  : .resourceDenied,
                    reason: "The addon refresh queue is full."
                )

            default: break
        }

        guard Self.recordCharge <= maximumRetainedBytes - retainedBytes, sequence < UInt64.max else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The host job queue is full."
            )
        }

        if records.isEmpty { sequence = 0 }
        sequence += 1
        let id      = UUID()
        records[id] = Record(
            owner     : owner,
            work      : work,
            enqueuedAt: instant.monotonic,
            sequence  : sequence,
            deadline  : admittedDeadline,
            phase     : .queued
        )
        return id
    }

    /// takeReady enforces both concurrency ceilings. Actions normally precede
    /// refreshes; a refresh waiting five seconds ages ahead of newly queued actions.
    /// Expired work is left for expire to report, never silently discarded here.
    public mutating func takeReady(at instant: Duration) -> Job? {
        guard let selected = readySelection(at: instant) else { return nil }

        return start(selected)
    }

    /// peekReady reports the current winner without consuming local scheduler capacity.
    func peekReady(at instant: Duration) -> Job? {
        guard let selected = readySelection(at: instant) else { return nil }

        return selected.record.job(id: selected.id)
    }

    /// takeReady conditionally starts the previously inspected canonical job.
    mutating func takeReady(
        expectedJobID: UUID,
        at instant   : Duration
    ) -> Job? {
        guard let selected = readySelection(at: instant), selected.id == expectedJobID else {
            return nil
        }

        return start(selected)
    }

    private func readySelection(at instant: Duration) -> (id: UUID, record: Record)? {
        guard busyOwners.count < 2, instant >= .zero else { return nil }

        var selected: (id: UUID, record: Record)?
        for (id, record) in records {
            guard record.phase == .queued,
                  record.deadline > instant,
                  !busyOwners.contains(record.owner)
            else { continue }

            if let current = selected {
                let candidatePriority = priority(record, at: instant)
                let previousPriority  = priority(current.record, at: instant)
                if candidatePriority > previousPriority
                    || (candidatePriority == previousPriority && record.sequence > current.record.sequence) {
                    continue
                }
            }
            selected = (id, record)
        }

        return selected
    }

    private mutating func start(_ selected: (id: UUID, record: Record)) -> Job {
        var running          = selected.record
        running.phase        = .running
        records[selected.id] = running
        busyOwners.insert(running.owner)
        return running.job(id: selected.id)
    }

    public func job(_ id: UUID) -> Job? { records[id]?.job(id: id) }

    /// nextDeadline excludes already reported stops, allowing the common host
    /// timer to disarm instead of repeatedly requesting the same termination.
    public var nextDeadline: Duration? {
        var earliest: Duration?
        for record in records.values where record.phase != .stopping {
            earliest = earliest.map { min($0, record.deadline) } ?? record.deadline
        }

        return earliest
    }

    /// finish consumes one host ticket after actual completion/exit. Late duplicate
    /// notifications cannot release a slot occupied by a different job for this owner.
    public mutating func finish(
        _ id : UUID,
        owner: AddonID
    ) throws {
        guard let record = records[id] else { return }
        guard record.owner == owner else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "The job belongs to another addon."
            )
        }
        guard record.phase != .queued else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "A queued job has not completed execution."
            )
        }

        records.removeValue(forKey: id)
        busyOwners.remove(owner)
    }

    /// expire returns definite unsent expirations and required process stops
    /// separately. A running job retains its admission until finish confirms exit.
    public mutating func expire(at instant: Duration) -> [Cancellation] {
        let ids = records.keys.filter { id in
            guard let record = records[id] else { return false }

            return record.phase != .stopping && record.deadline <= instant
        }
        return cancel(ids)
    }

    /// cancel removes future work after authorization is revoked by the runtime.
    /// Running work becomes stopping once; no completion can resurrect its queue.
    public mutating func cancel(owner: AddonID) -> [Cancellation] {
        cancel(records.keys.filter { records[$0]?.owner == owner })
    }

    /// releaseUnsentReservation ends a canonical host reservation before transport
    /// handoff. It must never be used for work whose external execution was started.
    mutating func releaseUnsentReservation(
        _ id : UUID,
        owner: AddonID
    ) {
        guard let record = records[id], record.owner == owner, record.phase != .queued else { return }

        records.removeValue(forKey: id)
        busyOwners.remove(owner)
    }

    /// cancelJob targets canonical coordinator work without cancelling unrelated jobs.
    mutating func cancelJob(
        _ id : UUID,
        owner: AddonID
    ) -> Cancellation? {
        guard records[id]?.owner == owner else { return nil }

        return cancel([id]).first
    }

    private mutating func cancel(_ ids: [UUID]) -> [Cancellation] {
        var cancelled: [Cancellation] = []
        for id in ids {
            guard var record = records[id], record.phase != .stopping else { continue }

            let requiresStop = record.phase == .running
            cancelled.append(Cancellation(job: record.job(id: id), requiresStop: requiresStop))
            if requiresStop {
                record.phase = .stopping
                records[id]  = record
            } else {
                records.removeValue(forKey: id)
            }
        }

        return cancelled
    }

    private func priority(
        _ record  : Record,
        at instant: Duration
    ) -> Int {
        switch record.work {
            case .command: return 1
            case .refresh: return instant - record.enqueuedAt >= .seconds(5) ? 0 : 2
        }
    }
}
