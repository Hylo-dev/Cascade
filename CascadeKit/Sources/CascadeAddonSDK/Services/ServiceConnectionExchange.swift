import CascadeContracts
import Foundation

/// One whole-operation arbiter and sequence for invocation and controls. Only an
/// invocation has a P1 ledger; no controls or event authority enter that ledger.
final class ServiceConnectionExchange: @unchecked Sendable {
    private struct Operation: @unchecked Sendable {
        let id: UUID
        let sequence: UInt64
        let ledger: ServiceInvocationLifecycle?
        let ticket: ServiceInvocationLifecycle.Ticket?
        var exposed = false
        var consumed = false
        var local: ServiceInvocationLifecycle.LocalFailure?
    }
    private let channel: any AddonServiceMessageChannel
    let generation: ConnectionGeneration
    private let lock = NSLock()
    private var operation: Operation?
    private var sequence: UInt64
    private var closed = false
    private var poisoned = false
    private var drainTask: Task<Void, Never>?

    init(channel: any AddonServiceMessageChannel, lastSequence: UInt64 = 0) throws {
        guard channel.invocationProfile == .v1_3, channel.subscriptionProfile == .v1_4 else { throw Self.failure(.versionConflict) }
        self.channel = channel; generation = channel.generation; sequence = lastSequence
    }

    private func descriptorsMatch() -> Bool {
        channel.generation == generation && channel.invocationProfile == .v1_3 && channel.subscriptionProfile == .v1_4
    }
    private func begin(invocation: ServiceInvocation? = nil, grantID: UUID? = nil) throws -> Operation {
        try lock.withLock {
            try Task.checkCancellation()
            guard !closed, !poisoned, sequence < UInt64.max else { throw Self.failure(.sessionRevoked) }
            guard operation == nil else { throw Self.failure(.resourceDenied) }
            var ledger: ServiceInvocationLifecycle?
            var ticket: ServiceInvocationLifecycle.Ticket?
            if let invocation, let grantID {
                let issued = ServiceInvocationLifecycle(generation: generation)
                ticket = try issued.begin(invocation, grantID: grantID); ledger = issued
            }
            sequence += 1
            let op = Operation(id: UUID(), sequence: sequence, ledger: ledger, ticket: ticket)
            operation = op
            return op
        }
    }

    func invoke(grantID: UUID, invocation: ServiceInvocation) async throws -> ServiceInvocationResult {
        let request = try ServiceInvocationRequest(grantID: grantID, invocation: invocation)
        let op = try begin(invocation: invocation, grantID: grantID)
        return try await run(op, kind: .invocation, encode: { try ServiceFrameCodec.encode(request, profile: .v1_3) }) { bytes in
            let reply = try ServiceFrameCodec.decodeInvocationReply(bytes, profile: .v1_3)
            try reply.validate(matching: request)
            if case .completed(let response) = reply.result, let ticket = op.ticket {
                _ = try op.ledger?.consume(.service(requestID: reply.requestID, response: response), ticket: ticket, generation: self.generation)
            } else { _ = op.ledger?.close() }
            return reply.result
        }
    }

    func control(_ request: ServiceControlRequest,
                 finalize: @escaping @Sendable (ServiceControlReply) throws -> Void = { _ in }) async throws -> ServiceControlReply {
        try request.validate()
        let op = try begin()
        return try await run(op, kind: .control, encode: { try ServiceSubscriptionFrameCodec.encode(request, profile: .v1_4) }) { bytes in
            let reply = try ServiceSubscriptionFrameCodec.decodeControlReply(bytes, profile: .v1_4)
            try reply.validate(matching: request)
            guard reply.phase == .terminal else { throw Self.failure(.invalidPayload) }
            if case .acquired(let grant) = reply.result, grant.generation != self.generation { throw Self.failure(.permissionDenied) }
            try finalize(reply)
            return reply
        }
    }

    /// Embedding plumbing, deliberately absent from AddonServiceClient.
    func acquire(_ operation: OperationRequest, owner: AddonID) async throws -> Grant {
        let request = try ServiceControlRequest(requestID: UUID(), action: .acquire(operation))
        let reply = try await control(request) { reply in
            if case .acquired(let grant) = reply.result, grant.owner != owner { throw Self.failure(.permissionDenied) }
        }
        switch reply.result {
        case .acquired(let grant): return grant
        case .refused(let code, let reason): throw AddonFailure(code: code, reason: reason)
        default: throw Self.failure(.outcomeUnknown)
        }
    }

    private func run<Result: Sendable>(_ op: Operation, kind: AddonServiceMessageKind,
        encode: @Sendable () throws -> Data, consume: @Sendable (Data) throws -> Result) async throws -> Result {
        try await withTaskCancellationHandler {
            do {
                guard descriptorsMatch() else { throw Self.failure(.sessionRevoked) }
                let frame = try encode()
                try lock.withLock {
                    guard descriptorsMatch(), let current = operation, current.id == op.id else { throw Self.failure(.sessionRevoked) }
                    if Task.isCancelled { cancelLocked(op.id) }
                    if let local = operation?.local { throw Self.localError(local) }
                    guard !closed, !poisoned else { throw Self.failure(.sessionRevoked) }
                    if let ticket = current.ticket { try current.ledger?.beginHandoff(ticket) }
                    operation?.exposed = true
                }
                let wire = try await channel.exchange(frame, kind: kind, sequence: op.sequence)
                guard descriptorsMatch() else { throw Self.failure(.outcomeUnknown) }
                let result: Result = try lock.withLock {
                    guard let current = operation, current.id == op.id else { throw Self.failure(.sessionRevoked) }
                    if let local = current.local { throw Self.localError(local) }
                    guard !closed, !poisoned else { throw Self.failure(.outcomeUnknown) }
                    switch wire {
                    case .rejectedBeforeHandoff:
                        if let ticket = current.ticket { _ = current.ledger?.observeHandoff(.rejectedBeforeHandoff, ticket: ticket) }
                        operation?.exposed = false
                        throw Self.failure(.dependencyUnavailable)
                    case .response(let bytes):
                        let value = try consume(bytes)
                        operation?.consumed = true
                        // Final projection and slot retirement are the same decision.
                        operation = nil
                        return value
                    }
                }
                return result
            } catch {
                let outcome: (any Error, Task<Void, Never>?) = lock.withLock {
                    guard let current = operation, current.id == op.id else { return (error, nil) }
                    _ = current.ledger?.close()
                    let failure: any Error
                    if let local = current.local { failure = Self.localError(local) }
                    else if current.exposed { failure = Self.failure(.outcomeUnknown) }
                    else { failure = error }
                    if current.exposed { poisoned = true }
                    if !descriptorsMatch() { poisoned = true }
                    return (failure, closed || poisoned ? startDrainLocked() : nil)
                }
                await outcome.1?.value
                lock.withLock { if operation?.id == op.id { operation = nil } }
                throw outcome.0
            }
        } onCancel: {
            self.lock.withLock { self.cancelLocked(op.id) }
        }
    }

    private func cancelLocked(_ id: UUID) {
        guard let op = operation, op.id == id, !op.consumed, op.local == nil else { return }
        if let ticket = op.ticket { _ = op.ledger?.cancel(ticket) }
        operation?.local = op.exposed ? .outcomeUnknown : .cancelled
        if op.exposed { poisoned = true; _ = startDrainLocked() }
    }
    func close() async {
        let task = lock.withLock {
            closed = true
            if let op = operation, !op.consumed, op.local == nil {
                _ = op.ledger?.close()
                operation?.local = op.exposed ? .outcomeUnknown : .closed
            }
            return startDrainLocked()
        }
        await task.value
    }
    private func startDrainLocked() -> Task<Void, Never> {
        if let drainTask { return drainTask }
        let channel = channel
        let task = Task { await channel.close() }
        drainTask = task
        return task
    }
    private static func localError(_ local: ServiceInvocationLifecycle.LocalFailure) -> any Error {
        switch local {
        case .cancelled: CancellationError()
        case .closed: failure(.sessionRevoked)
        case .notSent: failure(.dependencyUnavailable)
        case .outcomeUnknown: failure(.outcomeUnknown)
        }
    }
    private static func failure(_ code: AddonFailure.Code) -> AddonFailure {
        AddonFailure(code: code, reason: "The service connection cannot complete this operation")
    }
}
