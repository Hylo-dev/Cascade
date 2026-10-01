//
//  ActionJournal.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// ActionJournal preserves bounded command history independently of a connection.
/// The runtime actor owns this value and supplies authenticated owners/generations.
/// Sending is irreversible: losing the result never implies the external effect
/// was cancelled. This journal deliberately provides no automatic retry operation.
public struct ActionJournal: Sendable {

    public enum State: Equatable, Sendable {

        case queued
        case sent        (ConnectionGeneration)
        case acknowledged(ConnectionGeneration)
        case finished    (ActionOutcome)
    }

    public enum Admission: Equatable, Sendable {

        case admitted
        case duplicate(State)
    }

    private struct Key: Hashable {

        let owner: AddonID
        let id   : UUID
    }

    private struct Record {

        let request    : ActionRequest
        let deadline   : Duration
        let retainUntil: Duration
        var state      : State
        var charge     : Int
    }

    // Covers dictionary/key overhead, bounded identifiers, and the state machine.
    // Reserve a maximum-size completion before admission so a full journal cannot
    // lose the result of an operation that has already produced an external effect.
    private static let metadataCharge    = 4_096
    private static let completionReserve = 65_536

    private let maximumRetainedBytes: Int
    private let maximumCommandWait  : Duration

    private var records    : [Key: Record] = [:]
    private var ownerCounts: [AddonID: Int] = [:]

    public private(set) var retainedBytes = 0

    public var count: Int { records.count }

    public init(
        maximumRetainedBytes: Int = 8 * 1_024 * 1_024,
        maximumCommandWait  : Duration = .seconds(30)
    ) {
        self.maximumRetainedBytes = min(8 * 1_024 * 1_024, max(0, maximumRetainedBytes))
        self.maximumCommandWait   = min(.seconds(30), max(.zero, maximumCommandWait))
    }

    /// admit reserves history before a command enters the scheduler. A duplicate
    /// returns its original state without extending either of its deadlines.
    public mutating func admit(
        _ request : ActionRequest,
        owner     : AddonID,
        at instant: RuntimeInstant
    ) throws -> Admission {
        try request.validate()
        try request.publicationID.validateOwner(owner)

        guard instant.wall.timeIntervalSince1970.isFinite, instant.monotonic >= .zero else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "The runtime clock is invalid."
            )
        }

        expire(at: instant.monotonic)

        let key = Key(owner: owner, id: request.requestID)
        if let previous = records[key] {
            guard previous.request == request else {
                throw AddonFailure(
                    code  : .invalidPayload,
                    reason: "A request ID cannot identify a different command."
                )
            }

            return .duplicate(previous.state)
        }

        let remaining = request.deadline.timeIntervalSince(instant.wall)
        guard remaining > 0, maximumCommandWait > .zero else {
            throw AddonFailure(
                code  : .deadlineExceeded,
                reason: "The command deadline has passed."
            )
        }

        // Clamp before Double -> Duration conversion, including distant dates.
        let wait   = min(maximumCommandWait, .seconds(min(30, remaining)))
        let charge = Self.metadataCharge + request.input.count + Self.completionReserve
        guard ownerCounts[owner, default: 0] < 128,
              charge <= maximumRetainedBytes - retainedBytes
        else {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The command history budget is exhausted."
            )
        }

        records[key] = Record(
            request    : request,
            deadline   : instant.monotonic + wait,
            retainUntil: instant.monotonic + .seconds(600),
            state      : .queued,
            charge     : charge
        )
        ownerCounts[owner, default: 0] += 1
        retainedBytes += charge

        return .admitted
    }

    public func state(
        _ id : UUID,
        owner: AddonID
    ) -> State? {
        records[Key(owner: owner, id: id)]?.state
    }

    /// request returns bounded admitted input for host coordination and recovery.
    func request(
        _ id : UUID,
        owner: AddonID
    ) -> ActionRequest? {
        records[Key(owner: owner, id: id)]?.request
    }

    func deadline(
        _ id : UUID,
        owner: AddonID
    ) -> Duration? {
        records[Key(owner: owner, id: id)]?.deadline
    }

    /// storedCharge exposes one canonical record's existing retained-state charge.
    /// The runtime uses this projection instead of duplicating journal constants.
    func storedCharge(
        _ id : UUID,
        owner: AddonID
    ) -> Int? {
        records[Key(owner: owner, id: id)]?.charge
    }

    /// rejectNeverHandedOff makes a sent decision terminal only when the adapter
    /// synchronously proves that it never accepted or exposed the exact delivery.
    mutating func rejectNeverHandedOff(
        _ id      : UUID,
        owner     : AddonID,
        generation: ConnectionGeneration,
        failure   : AddonFailure
    ) -> Bool {
        let key = Key(owner: owner, id: id)
        guard records[key]?.state == .sent(generation) else { return false }

        finish(key, outcome: .rejected(reason: failure))

        return true
    }

    /// rollbackAdmission removes only an unsent new record after enqueue failed.
    /// The dispatcher calls this before publishing any admission result.
    mutating func rollbackAdmission(
        _ id : UUID,
        owner: AddonID
    ) {
        let key = Key(owner: owner, id: id)
        guard let record = records[key], record.state == .queued else { return }

        records.removeValue(forKey: key)
        retainedBytes -= record.charge

        let count          = ownerCounts[owner, default: 1] - 1
        ownerCounts[owner] = count > 0 ? count : nil
    }

    /// rejectUnsent makes invalidated queued intent definite without altering sent effects.
    mutating func rejectUnsent(
        _ id   : UUID,
        owner  : AddonID,
        failure: AddonFailure
    ) {
        let key = Key(owner: owner, id: id)
        guard records[key]?.state == .queued else { return }

        finish(key, outcome: .rejected(reason: failure))
    }

    /// nextDeadline lets the common host queue drive expiry; the journal owns no timer.
    public var nextDeadline: Duration? {
        var earliest: Duration?
        for record in records.values {
            let deadline: Duration
            if case .finished = record.state {
                deadline = record.retainUntil
            } else {
                deadline = record.deadline
            }

            earliest = earliest.map { min($0, deadline) } ?? deadline
        }

        return earliest
    }

    /// markSent must occur before handing the command to the transport. An uncertain
    /// transport failure after this transition is consequently never a safe retry.
    public mutating func markSent(
        _ id      : UUID,
        owner     : AddonID,
        generation: ConnectionGeneration,
        at instant: Duration
    ) throws {
        let key = Key(owner: owner, id: id)
        expire(key, at: instant)

        guard var record = records[key], record.state == .queued, instant >= .zero else {
            throw AddonFailure(
                code  : .sessionRevoked,
                reason: "The command is no longer waiting to be sent."
            )
        }

        record.state = .sent(generation)
        records[key] = record
    }

    public mutating func acknowledge(
        _ id      : UUID,
        owner     : AddonID,
        generation: ConnectionGeneration,
        at instant: Duration
    ) -> Bool {
        let key = Key(owner: owner, id: id)
        expire(key, at: instant)

        guard var record = records[key], record.state == .sent(generation), instant >= .zero else {
            return false
        }

        record.state = .acknowledged(generation)
        records[key] = record

        return true
    }

    /// complete accepts one result from the current authenticated generation only.
    /// Validation precedes mutation; malformed results cannot consume the completion.
    public mutating func complete(
        _ id      : UUID,
        owner     : AddonID,
        generation: ConnectionGeneration,
        outcome   : ActionOutcome,
        at instant: Duration
    ) throws -> Bool {
        let key = Key(owner: owner, id: id)
        expire(key, at: instant)

        guard let record = records[key],
              matches(record.state, generation: generation),
              instant >= .zero
        else { return false }

        try outcome.validate()
        finish(key, outcome: outcome)

        return true
    }

    /// canComplete validates the exact sent authority without expiring or mutating it.
    func canComplete(
        _ id      : UUID,
        owner     : AddonID,
        generation: ConnectionGeneration,
        at instant: Duration
    ) -> Bool {
        let key = Key(owner: owner, id: id)
        guard instant >= .zero,
              let record = records[key],
              instant < record.deadline,
              instant < record.retainUntil
        else { return false }

        return matches(record.state, generation: generation)
    }

    public mutating func connectionLost(
        owner     : AddonID,
        generation: ConnectionGeneration
    ) {
        for key in Array(records.keys) where key.owner == owner {
            guard let record = records[key],
                  matches(record.state, generation: generation)
            else { continue }

            finish(key, outcome: .outcomeUnknown)
        }
    }

    /// expire finalizes overdue work and later removes history. Retention is anchored
    /// to admission, so repeated lookups cannot retain results forever.
    public mutating func expire(at instant: Duration) {
        for key in Array(records.keys) { expire(key, at: instant) }
    }

    /// cancel preserves sent outcomes as unknown and retained terminal history. The
    /// runtime separately revokes authorization before calling this on addon disable.
    public mutating func cancel(owner: AddonID) {
        for key in Array(records.keys) where key.owner == owner {
            guard let record = records[key] else { continue }

            switch record.state {
                case .queued:
                    finish(
                        key,
                        outcome: .rejected(
                            reason: AddonFailure(
                                code  : .sessionRevoked,
                                reason: "The addon was disabled before the command was sent."
                            )
                        )
                    )

                case .sent, .acknowledged: finish(key, outcome: .outcomeUnknown)
                case .finished: break
            }
        }
    }

    private func matches(
        _ state   : State,
        generation: ConnectionGeneration
    ) -> Bool {
        state == .sent(generation) || state == .acknowledged(generation)
    }

    private mutating func expire(
        _ key     : Key,
        at instant: Duration
    ) {
        guard let record = records[key] else { return }

        if instant >= record.retainUntil {
            records.removeValue(forKey: key)
            retainedBytes -= record.charge

            let remaining          = ownerCounts[key.owner, default: 1] - 1
            ownerCounts[key.owner] = remaining > 0 ? remaining : nil
            return
        }

        guard instant >= record.deadline else { return }

        switch record.state {
            case .queued:
                finish(
                    key,
                    outcome: .rejected(
                        reason: AddonFailure(
                            code  : .deadlineExceeded,
                            reason: "The command expired before it was sent."
                        )
                    )
                )

            case .sent, .acknowledged: finish(key, outcome: .outcomeUnknown)
            case .finished: break
        }
    }

    private mutating func finish(
        _ key  : Key,
        outcome: ActionOutcome
    ) {
        guard var record = records[key] else { return }

        let resultBytes: Int
        switch outcome {
            case .completed(let payload): resultBytes = payload.count
            case .rejected(let failure): resultBytes = failure.reason.utf8.count + 128
            case .outcomeUnknown: resultBytes = 0
        }

        let charge = Self.metadataCharge + record.request.input.count + resultBytes
        retainedBytes += charge - record.charge
        record.charge = charge
        record.state  = .finished(outcome)
        records[key]  = record
    }
}
