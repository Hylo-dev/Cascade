//
//  MessageAddonStorageClient.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// Concrete storage messages for one injected, already authenticated connection.
///
/// One lock serializes the scalar lifecycle and a separate whole-operation slot. No waiter
/// queue, payload history or retry exists. Cancellation chooses a local outcome but SDK return
/// waits for physical exchange disposal; it never proves rollback. Exact response consumption
/// precedes final result authority: explicit close can still win that final decision.
///
/// The embedding must prepay source allocations, SDK workspace and returned Data lifetimes
/// before using this client. Logical admission is not a quota reservation, authentication or
/// whole-process memory bound. Physical correlation/receipt guarantees come from the channel.
public final class MessageAddonStorageClient: AddonStorageClient, @unchecked Sendable {
    private let channel: any AddonStorageMessageChannel
    private let generation: ConnectionGeneration
    private let profile: StorageFrameProfile
    /// This intentionally non-Sendable ledger is accessed only inside lock.withLock.
    private let lifecycle: StorageRequestLifecycle
    private let lock = NSLock()
    private var closed = false
    private var poisoned = false
    /// Exact slot identity prevents an old operation's cleanup from clearing newer work.
    private var operationID: UUID?
    private var currentTicket: StorageRequestLifecycle.Ticket?
    private var localCompletion: StorageRequestLifecycle.LocalFailure?
    private var drainTask: Task<Void, Never>?

    public init(channel: any AddonStorageMessageChannel) throws {
        let generation = channel.generation
        let lifecycle = try StorageRequestLifecycle(generation: generation, profile: channel.profile)
        self.channel = channel
        self.generation = generation
        self.profile = .v1_1
        self.lifecycle = lifecycle
    }

    public func read(key: String) async throws -> Data? {
        let response = try await perform(.read, key: key, value: nil)
        if response.result == .failure { throw hostFailure(response) }
        return response.value
    }

    public func write(_ data: Data, key: String) async throws {
        let response = try await perform(.write, key: key, value: data)
        if response.result == .failure { throw hostFailure(response) }
    }

    public func remove(key: String) async throws {
        let response = try await perform(.remove, key: key, value: nil)
        if response.result == .failure { throw hostFailure(response) }
    }

    /// Revoke admission synchronously and await the single physical drain. Caller buffers and
    /// the embedding scope still belong to their actual operation lifetime, not this flag.
    public func close() async {
        lock.withLock {
            closed = true
            record(lifecycle.close())
        }
        await drain()
    }

#if DEBUG
    /// Inert task-local checkpoints observe production boundaries without replacing disposal.
    @TaskLocal internal static var preparedObserver: (@Sendable () async -> Void)?
    @TaskLocal internal static var consumedObserver: (@Sendable () async -> Void)?
    @TaskLocal internal static var drainWaitObserver: (@Sendable () -> Void)?
    @TaskLocal internal static var encodingObserver: (@Sendable () -> Void)?
#endif

    private func perform(_ operation: StorageOperation, key: String, value: Data?) async throws -> StorageResponse {
        let id = try acquire()
        do {
            let request = try StorageRequest(requestID: UUID(), operation: operation, key: key, value: value)
            let ticket = try lock.withLock {
                guard !closed, !poisoned else { throw failure(.sessionRevoked) }
                try Task.checkCancellation()
                let issued = try lifecycle.begin(request)
                currentTicket = issued
                return issued
            }
            return try await withTaskCancellationHandler {
                try await exchange(request, ticket: ticket, operationID: id)
            } onCancel: {
                self.lock.withLock {
                    guard self.currentTicket == ticket else { return }
                    self.record(self.lifecycle.cancel(ticket))
                }
            }
        } catch {
            await conclude(id)
            throw error
        }
    }

    private func acquire() throws -> UUID {
        try lock.withLock {
            guard !closed, !poisoned else { throw failure(.sessionRevoked) }
            try Task.checkCancellation()
            guard operationID == nil else { throw failure(.resourceDenied) }
            let id = UUID()
            operationID = id
            localCompletion = nil
            return id
        }
    }

    private func exchange(
        _ request: StorageRequest,
        ticket: StorageRequestLifecycle.Ticket,
        operationID: UUID
    ) async throws -> StorageResponse {
        guard channel.generation == generation, channel.profile == profile else {
            throw await poisonFailure(ticket, readCode: .sessionRevoked, beforeHandoff: true)
        }
#if DEBUG
        Self.encodingObserver?()
#endif
        let frame: Data
        do { frame = try StorageFrameCodec.encode(request, profile: profile) }
        catch {
            lock.withLock { record(lifecycle.cancel(ticket)) }
            throw error
        }
#if DEBUG
        await Self.preparedObserver?()
#endif
        guard channel.generation == generation, channel.profile == profile else {
            throw await poisonFailure(ticket, readCode: .sessionRevoked, beforeHandoff: true)
        }
        try lock.withLock {
            if Task.isCancelled { record(lifecycle.cancel(ticket)) }
            if let localCompletion { throw localFailure(localCompletion) }
            guard !closed, !poisoned else { throw failure(.sessionRevoked) }
            try lifecycle.beginHandoff(ticket)
        }

        let result: AddonStorageMessageExchangeResult
        do { result = try await channel.exchange(frame, sequence: ticket.sequence) }
        catch { throw await poisonFailure(ticket, readCode: .dependencyUnavailable) }

        guard channel.generation == generation, channel.profile == profile else {
            throw await poisonFailure(ticket, readCode: .sessionRevoked)
        }
        let reply: Data
        switch result {
        case .rejectedBeforeHandoff:
            let completion = lock.withLock {
                record(lifecycle.observeHandoff(.rejectedBeforeHandoff, ticket: ticket))
                return localCompletion ?? .notSent
            }
            throw localFailure(completion)
        case .response(let bytes): reply = bytes
        }

        let response: StorageResponse
        do {
            response = try StorageFrameCodec.decodeResponse(reply, profile: profile)
            // Correlation/semantic validation and retirement are synchronous in one domain.
            // A reply may consume the attempting ticket before any accepted observation.
            _ = try lock.withLock {
                try lifecycle.consume(response, generation: generation, sequence: ticket.sequence)
            }
        } catch { throw await poisonFailure(ticket, readCode: .invalidPayload) }
#if DEBUG
        await Self.consumedObserver?()
#endif
        try await finalize(operationID)
        return response
    }

    /// Caller holds the lock; keep the first local outcome and never complete an old ticket.
    private func record(_ completion: StorageRequestLifecycle.LocalCompletion?) {
        guard let completion, completion.ticket == currentTicket, localCompletion == nil else { return }
        localCompletion = completion.failure
    }

    /// Ledger consumption does not release the operational slot. Result delivery, including a
    /// host failure, and close use the same lock. Later cancellation cannot relabel a consumed
    /// result; cancellation that won earlier has a stored outcome and its response is discarded.
    private func finalize(_ id: UUID) async throws {
        let decision: (revoked: Bool, completion: StorageRequestLifecycle.LocalFailure?) = lock.withLock {
            let revoked = closed || poisoned
            let completion = localCompletion ?? (revoked ? .closed : nil)
            if !revoked { clearOperation(id) }
            return (revoked, completion)
        }
        if decision.revoked {
            await drain()
            lock.withLock { clearOperation(id) }
        }
        if let completion = decision.completion { throw localFailure(completion) }
    }

    /// Generic faults have no non-exposure proof. Preserve an earlier local completion;
    /// otherwise unresolved mutations are unknown. A poison-induced ledger close is not an
    /// explicit user close and must not disguise a read validation/transport error as one.
    private func poisonFailure(
        _ ticket: StorageRequestLifecycle.Ticket,
        readCode: AddonFailure.Code,
        beforeHandoff: Bool = false
    ) async -> any Error {
        let error: any Error = lock.withLock {
            poisoned = true
            _ = lifecycle.close()
            if let localCompletion { return localFailure(localCompletion) }
            if closed { return failure(.sessionRevoked) }
            return failure(ticket.operation == .read || beforeHandoff ? readCode : .outcomeUnknown)
        }
        await drain()
        return error
    }

    private func conclude(_ id: UUID) async {
        let revoked = lock.withLock {
            guard operationID == id else { return false }
            if let currentTicket { _ = lifecycle.cancel(currentTicket) }
            let revoked = closed || poisoned
            if !revoked { clearOperation(id) }
            return revoked
        }
        if revoked {
            await drain()
            lock.withLock { clearOperation(id) }
        }
    }

    /// Caller holds the lock. Exact identity prevents stale catch/finalization cleanup.
    private func clearOperation(_ id: UUID) {
        guard operationID == id else { return }
        operationID = nil
        currentTicket = nil
        localCompletion = nil
    }

    private func drain() async {
        let task: Task<Void, Never> = lock.withLock {
            if let drainTask { return drainTask }
            let channel = self.channel
            let created = Task { await channel.close() }
            drainTask = created
            return created
        }
#if DEBUG
        Self.drainWaitObserver?()
#endif
        await task.value
    }

    private func localFailure(_ completion: StorageRequestLifecycle.LocalFailure) -> any Error {
        switch completion {
        case .cancelled: return CancellationError()
        case .closed: return failure(.sessionRevoked)
        case .notSent: return failure(.dependencyUnavailable)
        case .outcomeUnknown: return failure(.outcomeUnknown)
        }
    }

    private func hostFailure(_ response: StorageResponse) -> AddonFailure {
        AddonFailure(code: response.failureCode ?? .invalidPayload,
                     reason: response.failureReason ?? "The storage host refused this request.")
    }

    private func failure(_ code: AddonFailure.Code) -> AddonFailure {
        AddonFailure(code: code, reason: "The storage client cannot complete this operation (\(code.rawValue)).")
    }
}
