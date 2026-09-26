//
//  ServiceInvocationLifecycle.swift
//  Cascade
//

import CascadeContracts
import Foundation

/// ServiceInvocationLifecycle owns one scalar ledger in its caller's serialization domain.
/// Deliberately non-Sendable: callers serialize every transition. No payload, grant snapshot,
/// response, callback or asynchronous work is retained. Local tickets authenticate no peer.
/// Logical retirement never drains physical bytes, refunds quota or rolls back service effects;
/// a future concrete client must separately serialize whole-operation finalization and drain.
final class ServiceInvocationLifecycle {
    /// Ticket binds exact local identity independently of publication generations and wire sequences.
    /// Bounded contract/operation metadata comes from existing invocation validation.
    struct Ticket: Equatable, Sendable {
        fileprivate let issuer: UUID
        fileprivate let nonce : UUID
        let generation        : ConnectionGeneration
        let requestID         : UUID
        let grantID           : UUID
        let contractID        : String
        let operation         : String
    }

    /// HandoffObservation records trusted request-side exposure; only non-exposure establishes notSent.
    /// Generic errors and host reply refusal provide no such evidence.
    enum HandoffObservation: Sendable {
        case accepted
        case rejectedBeforeHandoff
    }
    enum LocalFailure: Equatable, Sendable {
        case cancelled
        case closed
        case notSent
        case outcomeUnknown
    }
    struct LocalCompletion: Equatable, Sendable {
        let ticket: Ticket
        let failure: LocalFailure
    }
    /// ResponseDisposition discards exact late results without revising an earlier local unknown outcome.
    /// This is a logical disposition, never a physical disposal acknowledgment.
    enum ResponseDisposition: Equatable, Sendable {
        case deliver
        case discardCancelled
    }

    private enum Phase {
        case prepared
        case attempting
        case accepted
    }
    private struct Pending {
        let ticket: Ticket
        var phase: Phase
        var locallyCancelled: Bool
    }
    private let generation: ConnectionGeneration
    private let issuer = UUID()
    private var pending: Pending?
    private var closed = false

    /// init stores a descriptive service-domain generation; actual grant authority remains with the broker.
    init(generation: ConnectionGeneration) { self.generation = generation }

    /// begin admits without queued waiting or retained request-ID history. A fresh nonce distinguishes reuse
    /// of the same requestID/grantID; canonical broker history remains responsible for replay.
    func begin(
        _ invocation: ServiceInvocation,
        grantID     : UUID
    ) throws -> Ticket {
        guard !closed else { throw Self.failure(.sessionRevoked) }
        guard pending == nil else { throw Self.failure(.resourceDenied) }
        try invocation.validate()
        let ticket = Ticket(
            issuer: issuer,
            nonce: UUID(),
            generation: generation,
            requestID: invocation.requestID,
            grantID: grantID,
            contractID: invocation.contractID,
            operation: invocation.operation
        )
        pending = Pending(
            ticket          : ticket,
            phase           : .prepared,
            locallyCancelled: false
        )
        return ticket
    }

    /// beginHandoff must precede possible exposure or suspension. No operation name implies purity.
    func beginHandoff(_ ticket: Ticket) throws {
        guard !closed, let current = pending, current.ticket == ticket else {
            throw Self.failure(.sessionRevoked)
        }
        guard current.phase == .prepared else { throw Self.failure(.invalidPayload) }
        pending?.phase = .attempting
    }

    /// observeHandoff permits a completion to beat acceptance. Late observations cannot change its disposition
    /// or disturb a newer ticket; rejection after accepted exposure cannot prove non-exposure.
    func observeHandoff(
        _ observation: HandoffObservation,
        ticket       : Ticket
    ) -> LocalCompletion? {
        guard !closed, let current = pending, current.ticket == ticket, current.phase == .attempting
        else {
            return nil
        }
        switch observation {
        case .accepted:
            pending?.phase = .accepted
            return nil
        case .rejectedBeforeHandoff:
            pending = nil
            return current.locallyCancelled
                ? nil : LocalCompletion(ticket: ticket, failure: .notSent)
        }
    }

    /// consume checks a caller-owned completion within its prepaid lifetime, after any external raw decoding.
    /// Correlation alone does not validate the value: both existing checks precede retirement.
    /// Invalid input preserves capacity; attempting allows a response before acceptance returns.
    func consume(
        _ completion: InvocationCompletion,
        ticket: Ticket,
        generation: ConnectionGeneration
    ) throws -> ResponseDisposition {
        guard !closed, let current = pending, current.ticket == ticket,
            generation == self.generation
        else {
            throw Self.failure(.sessionRevoked)
        }
        guard current.phase != .prepared else { throw Self.failure(.invalidPayload) }
        try completion.validate()
        try completion.validateCorrelation(
            .service(
                requestID: ticket.requestID,
                contractID: ticket.contractID,
                operation: ticket.operation
            )
        )
        pending = nil
        return current.locallyCancelled ? .discardCancelled : .deliver
    }

    /// cancel retires prepared work immediately. Every possibly exposed service is unknown,
    /// including operations named read, and remains occupied until exact result/rejection/close.
    func cancel(_ ticket: Ticket) -> LocalCompletion? {
        guard !closed, let current = pending, current.ticket == ticket, !current.locallyCancelled
        else {
            return nil
        }
        if current.phase == .prepared {
            pending = nil
            return LocalCompletion(ticket: ticket, failure: .cancelled)
        }
        pending?.locallyCancelled = true
        return LocalCompletion(ticket: ticket, failure: .outcomeUnknown)
    }

    /// close permanently revokes the ledger with at most one local completion per ticket; no physical claim.
    func close() -> LocalCompletion? {
        guard !closed else { return nil }
        closed = true
        let current = pending
        pending = nil
        guard let current, !current.locallyCancelled else { return nil }
        return LocalCompletion(
            ticket: current.ticket,
            failure: current.phase == .prepared ? .closed : .outcomeUnknown
        )
    }

    private static func failure(_ code: AddonFailure.Code) -> AddonFailure {
        AddonFailure(
            code  : code,
            reason: "The service lifecycle cannot accept this transition."
        )
    }
}
