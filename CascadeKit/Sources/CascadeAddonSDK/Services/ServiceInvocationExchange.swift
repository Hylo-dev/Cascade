import CascadeContracts
import Foundation

/// Internal invocation executor, deliberately not a partial public service client.
/// A caller/embedding must protect codec/source/returned buffers before allocation.
/// One lock arbitrates logical result, close and the whole-operation slot. The slot
/// survives ledger retirement through physical drain and final synchronous delivery.
internal final class ServiceInvocationExchange: @unchecked Sendable {
    private let channel: any AddonServiceInvocationMessageChannel
    private let generation: ConnectionGeneration
    private let profile: ServiceInvocationFrameProfile
    private let lock = NSLock()
    private struct Operation: @unchecked Sendable {
        let id: UUID
        let ledger: ServiceInvocationLifecycle
        let ticket: ServiceInvocationLifecycle.Ticket
        let sequence: UInt64
        var exposed = false
        var consumed = false
        var local: ServiceInvocationLifecycle.LocalFailure?
    }
    private var operation: Operation?
    private var lastSequence: UInt64
    private var closed = false
    private var poisoned = false
    private var drainTask: Task<Void, Never>?

    /// Sequence is descriptive wire state, never host authority. A restored/exhausted
    /// connection must fail closed rather than wrap; there is no recovery/retry here.
    init(channel: any AddonServiceInvocationMessageChannel, lastSequence: UInt64 = 0) throws {
        guard channel.profile == .v1_3 else { throw Self.failure(.versionConflict) }
        self.channel = channel
        generation = channel.generation
        profile = .v1_3
        self.lastSequence = lastSequence
    }

#if DEBUG
    @TaskLocal internal static var preparedObserver: (@Sendable () async -> Void)?
    @TaskLocal internal static var consumedObserver: (@Sendable () async -> Void)?
#endif

    func invoke(grantID: UUID, invocation: ServiceInvocation) async throws -> ServiceInvocationResult {
        let request = try ServiceInvocationRequest(grantID: grantID, invocation: invocation)
        let admitted = try lock.withLock {
            guard !closed, !poisoned else { throw Self.failure(.sessionRevoked) }
            try Task.checkCancellation()
            guard operation == nil else { throw Self.failure(.resourceDenied) }
            guard lastSequence < UInt64.max else { throw Self.failure(.sessionRevoked) }
            let ledger = ServiceInvocationLifecycle(generation: generation)
            let ticket = try ledger.begin(invocation, grantID: grantID)
            lastSequence += 1
            let issued = Operation(id: UUID(), ledger: ledger, ticket: ticket, sequence: lastSequence)
            operation = issued
            return issued
        }
        return try await withTaskCancellationHandler {
            do {
                let result = try await perform(request, admitted: admitted)
                return try await finalize(admitted.id, result: result)
            } catch {
                await conclude(admitted.id)
                throw error
            }
        } onCancel: { self.cancel(admitted.id) }
    }

    func close() async {
        lock.withLock {
            closed = true
            if let op = operation, !op.consumed { record(op.ledger.close(), id: op.id) }
            _ = startDrainLocked()
        }
        await drain()
    }

    private func descriptorsMatch() -> Bool { channel.generation == generation && channel.profile == profile }

    private func perform(_ request: ServiceInvocationRequest, admitted: Operation) async throws -> ServiceInvocationResult {
        guard descriptorsMatch() else { throw await poison(admitted.id, beforeExposure: true) }
        let frame = try ServiceFrameCodec.encode(request, profile: profile)
#if DEBUG
        await Self.preparedObserver?()
#endif
        guard descriptorsMatch() else { throw await poison(admitted.id, beforeExposure: true) }
        try lock.withLock {
            guard let op = operation, op.id == admitted.id else { throw Self.failure(.sessionRevoked) }
            if Task.isCancelled { record(op.ledger.cancel(op.ticket), id: op.id) }
            if let local = operation?.local { throw Self.localFailure(local) }
            guard !closed, !poisoned else { throw Self.failure(.sessionRevoked) }
            try op.ledger.beginHandoff(op.ticket)
            operation?.exposed = true
        }
        let wire: AddonServiceInvocationMessageExchangeResult
        do { wire = try await channel.exchange(frame, sequence: admitted.sequence) }
        catch { throw await poison(admitted.id) }
        guard descriptorsMatch() else { throw await poison(admitted.id) }
        switch wire {
        case .rejectedBeforeHandoff:
            let local = lock.withLock {
                record(admitted.ledger.observeHandoff(.rejectedBeforeHandoff, ticket: admitted.ticket), id: admitted.id)
                return operation?.local ?? .notSent
            }
            throw Self.localFailure(local)
        case .response(let bytes):
            let reply: ServiceInvocationReply
            do {
                reply = try ServiceFrameCodec.decodeInvocationReply(bytes, profile: profile)
                // Crucial: P1 structural decode does not validate outer/nested agreement.
                // Entire wire correlation must precede projecting the nested response.
                try reply.validate(matching: request)
                try lock.withLock {
                    guard let op = operation, op.id == admitted.id else { throw Self.failure(.sessionRevoked) }
                    if case .completed(let response) = reply.result {
                        _ = try op.ledger.consume(.service(requestID: reply.requestID, response: response),
                                                  ticket: op.ticket, generation: generation)
                    } else { _ = op.ledger.close() } // cleanup's synthetic unknown cannot relabel known wire results
                    operation?.consumed = true
                }
            } catch { throw await poison(admitted.id) }
#if DEBUG
            await Self.consumedObserver?()
#endif
            return reply.result
        }
    }

    /// Only the first local outcome wins. Old callbacks have no new-operation authority.
    private func record(_ completion: ServiceInvocationLifecycle.LocalCompletion?, id: UUID) {
        guard let completion, let op = operation, op.id == id, completion.ticket == op.ticket,
              op.local == nil, !op.consumed else { return }
        operation?.local = completion.failure
    }
    private func cancel(_ id: UUID) {
        lock.withLock {
            guard let op = operation, op.id == id, !op.consumed else { return }
            record(op.ledger.cancel(op.ticket), id: id)
            if op.exposed {
                poisoned = true
                _ = startDrainLocked()
            }
        }
    }
    private func poison(_ id: UUID, beforeExposure: Bool = false) async -> any Error {
        let error: any Error = lock.withLock {
            poisoned = true
            guard let op = operation, op.id == id else { return Self.failure(.sessionRevoked) }
            _ = op.ledger.close()
            if let local = op.local { return Self.localFailure(local) }
            return Self.failure(beforeExposure ? .sessionRevoked : .outcomeUnknown)
        }
        await drain()
        return error
    }
    private func finalize(_ id: UUID, result: ServiceInvocationResult) async throws -> ServiceInvocationResult {
        // Result/close selection and slot retirement are one lock decision. A close
        // cannot interleave between a drain check and synchronous result authority.
        let decision = try lock.withLock { () -> (drain: Bool, local: ServiceInvocationLifecycle.LocalFailure?) in
            guard let op = operation, op.id == id else { throw Self.failure(.sessionRevoked) }
            if closed || poisoned { return (true, op.local ?? .closed) }
            operation = nil
            return (false, op.local)
        }
        if decision.drain {
            await drain()
            lock.withLock { if operation?.id == id { operation = nil } }
        }
        if let local = decision.local { throw Self.localFailure(local) }
        return result
    }
    private func conclude(_ id: UUID) async {
        let needsDrain = lock.withLock {
            guard let op = operation, op.id == id else { return false }
            _ = op.ledger.close()
            return closed || poisoned
        }
        if needsDrain { await drain() }
        lock.withLock { if operation?.id == id { operation = nil } }
    }
    /// Caller holds lock. An unstructured task inherits no cancellation state from
    /// a cancelling caller; every close/fault/cancel joins this same physical drain.
    private func startDrainLocked() -> Task<Void, Never> {
        if let drainTask { return drainTask }
        let channel = self.channel
        let created = Task { await channel.close() }
        drainTask = created
        return created
    }
    private func drain() async { await lock.withLock { startDrainLocked() }.value }
    private static func localFailure(_ failure: ServiceInvocationLifecycle.LocalFailure) -> any Error {
        switch failure {
        case .cancelled: CancellationError()
        case .closed: Self.failure(.sessionRevoked)
        case .notSent: Self.failure(.dependencyUnavailable)
        case .outcomeUnknown: Self.failure(.outcomeUnknown)
        }
    }
    private static func failure(_ code: AddonFailure.Code) -> AddonFailure {
        AddonFailure(code: code, reason: "The service exchange cannot complete this operation.")
    }
}
