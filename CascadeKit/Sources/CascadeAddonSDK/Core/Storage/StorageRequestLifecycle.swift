//
//  StorageRequestLifecycle.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// StorageRequestLifecycle owns one scalar request ledger inside its caller's serialization domain.
/// This reference type is intentionally not Sendable. It retains no request/response buffers and
/// authenticates no peer. The future channel owner must separately drain physical bytes and receipts;
/// clearing this ledger, including close, neither releases their quota nor rolls back a host mutation.
final class StorageRequestLifecycle {
    /// Ticket binds one issued request to this exact ledger without retaining its key or value.
    /// Its UUIDs provide local correlation, not permission or a history-wide uniqueness guarantee.
    struct Ticket: Equatable, Sendable {
        fileprivate let issuer: UUID
        fileprivate let nonce: UUID
        let generation: ConnectionGeneration
        let sequence  : UInt64
        let requestID : UUID
        let operation : StorageOperation
    }

    /// HandoffObservation must describe an actual transport observation, never an inferred error.
    enum HandoffObservation: Sendable {
        case accepted
        case rejectedBeforeHandoff
    }

    /// LocalFailure separates a local wait cancellation from a possibly completed host mutation.
    enum LocalFailure: Equatable, Sendable {
        case cancelled
        case closed
        case notSent
        case outcomeUnknown
    }

    /// LocalCompletion is emitted at most once per ticket across cancellation, rejection and close.
    struct LocalCompletion: Equatable, Sendable {
        let ticket : Ticket
        let failure: LocalFailure
    }

    /// ResponseDisposition decides user delivery without copying or retaining the caller's response.
    /// discardCancelled permits draining that exact reply; it is not a physical release receipt.
    enum ResponseDisposition: Equatable, Sendable {
        case deliver
        case discardCancelled
    }

    private enum Phase {
        case prepared
        case attempting
        case accepted
    }

    /// Pending remains occupied after in-flight cancellation until exact reply, rejection or close.
    private struct Pending {
        let ticket          : Ticket
        var phase           : Phase
        var locallyCancelled: Bool
    }

    private let generation        : ConnectionGeneration
    private let issuer            : UUID = UUID()
    private var lastIssuedSequence: UInt64 = 0
    private var closed            : Bool = false
    private var pending           : Pending?

    /// StorageRequestLifecycle requires the existing storage profile for this supplied generation.
    /// Configuration is descriptive; the caller remains responsible for authenticating its channel.
    init(
        generation: ConnectionGeneration,
        profile   : StorageFrameProfile?
    ) throws {
        guard profile == .v1_1 else { throw Self.failure(.versionConflict) }
        self.generation = generation
    }

    /// begin validates admission before advancing the counter or retaining a scalar ticket.
    /// Issued sequences are never reused, including gaps left by cancellation or proven rejection.
    func begin(_ request: StorageRequest) throws -> Ticket {
        guard !closed else { throw Self.failure(.sessionRevoked) }
        guard pending == nil else { throw Self.failure(.resourceDenied) }
        try request.validate()
        let sequence = try Self.nextSequence(after: lastIssuedSequence)
        let ticket   = Ticket(
            issuer    : issuer,
            nonce     : UUID(),
            generation: generation,
            sequence  : sequence,
            requestID : request.requestID,
            operation : request.operation
        )
        pending = Pending(
            ticket          : ticket,
            phase           : .prepared,
            locallyCancelled: false
        )
        lastIssuedSequence = sequence
        return ticket
    }

    /// beginHandoff marks possible exposure before the caller may send bytes or suspend.
    /// A generic failure after this boundary cannot establish that a mutation was never sent.
    func beginHandoff(_ ticket: Ticket) throws {
        guard !closed, let current = pending, current.ticket == ticket else {
            throw Self.failure(.sessionRevoked)
        }
        guard current.phase == .prepared else { throw Self.failure(.invalidPayload) }
        pending?.phase = .attempting
    }

    /// observeHandoff tolerates a reply that arrives before the send call returns its observation.
    /// Only the current attempting ticket can change; old observations cannot retire newer work.
    func observeHandoff(
        _ observation: HandoffObservation,
        ticket       : Ticket
    ) -> LocalCompletion? {
        guard !closed, let current = pending, current.ticket == ticket, current.phase == .attempting else {
            return nil
        }
        switch observation {
        case .accepted:
            pending?.phase = .accepted
            return nil
        case .rejectedBeforeHandoff:
            pending = nil
            return current.locallyCancelled
                ? nil
                : LocalCompletion(
                    ticket : current.ticket,
                    failure: .notSent
                )
        }
    }

    /// consume validates the caller-owned `StorageResponse` and all scalar correlation before
    /// retiring work.
    /// A reply is valid while attempting because it may beat the send observation to the caller.
    /// Invalid or stale replies leave current capacity occupied; raw callers must decode through
    /// `StorageFrameCodec` first.
    func consume(
        _ response: StorageResponse,
        generation: ConnectionGeneration,
        sequence  : UInt64
    ) throws -> ResponseDisposition {
        guard !closed, let current = pending, generation == self.generation else {
            throw Self.failure(.sessionRevoked)
        }
        guard current.ticket.sequence == sequence, current.ticket.requestID == response.requestID,
            current.ticket.operation == response.operation, current.phase != .prepared
        else { throw Self.failure(.invalidPayload) }
        try response.validate()
        pending = nil
        return current.locallyCancelled ? .discardCancelled : .deliver
    }

    /// cancel completes only the local wait once. In-flight work retains the pending slot.
    /// Reads report cancellation; possibly handed-off mutations conservatively report uncertainty.
    func cancel(_ ticket: Ticket) -> LocalCompletion? {
        guard !closed, let current = pending, current.ticket == ticket, !current.locallyCancelled else {
            return nil
        }
        if current.phase == .prepared {
            pending = nil
            return LocalCompletion(
                ticket : current.ticket,
                failure: .cancelled
            )
        }
        pending?.locallyCancelled = true
        return LocalCompletion(
            ticket : current.ticket,
            failure: current.ticket.operation == .read ? .cancelled : .outcomeUnknown
        )
    }

    /// close irreversibly revokes scalar authority without claiming physical channel disposal.
    /// Already cancelled callers receive no second completion, regardless of eventual host outcome.
    func close() -> LocalCompletion? {
        guard !closed else { return nil }
        closed = true
        let current = pending
        pending = nil
        guard let current, !current.locallyCancelled else { return nil }
        let failure: LocalFailure =
            current.phase == .prepared || current.ticket.operation == .read ? .closed : .outcomeUnknown
        return LocalCompletion(
            ticket : current.ticket,
            failure: failure
        )
    }

    /// nextSequence is the checked arithmetic used by admission, with no seeded-session bypass.
    static func nextSequence(after lastIssued: UInt64) throws -> UInt64 {
        guard lastIssued < UInt64.max else { throw Self.failure(.resourceDenied) }
        return lastIssued + 1
    }

    private static func failure(_ code: AddonFailure.Code) -> AddonFailure {
        AddonFailure(
            code  : code,
            reason: "The storage lifecycle cannot accept this transition."
        )
    }
}
