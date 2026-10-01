//
//  RecordingClient.swift
//  ServiceConsumer
//

import Foundation
import Testing
import CascadeAddonSDK
import CascadeContracts
import FocusSessionsExampleContract
import FocusSessionsExampleProvider

actor RecordingClient: AddonServiceClient {

    var calls: [(ServiceInvocation, Grant)] = []

    let failure  : AddonFailure?
    let response : ServiceResponse?
    let suspended: Bool

    private var waiter  : CheckedContinuation<Void, Never>?
    private var signal  : RefreshSignal?
    private var observer: CheckedContinuation<RefreshSignal, Never>?
    private var released = false

    init(
        failure  : AddonFailure? = nil,
        response : ServiceResponse? = nil,
        suspended: Bool = false
    ) {
        self.failure   = failure
        self.response  = response
        self.suspended = suspended
    }

    func invoke(
        _ invocation: ServiceInvocation,
        grant       : Grant
    ) async throws -> ServiceResponse {
        calls.append((invocation, grant))
        if suspended && !released {
            await withCheckedContinuation {
                waiter = $0
                publish(.invoked)
            }
        }

        if let failure { throw failure }
        if let response { return response }

        let provider   = FocusSessionsExampleProvider(clock: { instant })
        let result     = try await provider.handle(.serviceRequest(invocation), context: context(self, []))
        let completion = try #require(result.completion)
        try completion.validateCorrelation(
            .service(
                requestID : invocation.requestID,
                contractID: invocation.contractID,
                operation : invocation.operation
            )
        )
        #expect(result.publications.isEmpty && result.operations.isEmpty && result.checkpoint == nil)
        guard case .service(_, let response) = completion else { throw CancellationError() }

        return response
    }

    // One rendezvous per client: cache the first signal so either arrival order works.
    private func publish(_ next: RefreshSignal) {
        guard signal == nil else { return }

        signal = next
        observer?.resume(returning: next)
        observer = nil
    }

    func refreshFinished(_ result: Result<ProviderOutput, any Error>) { publish(.completed(result)) }

    func invokedOrFinished() async -> RefreshSignal {
        if let signal { return signal }

        return await withCheckedContinuation { observer = $0 }
    }

    func release() {
        released = true
        waiter?.resume()
        waiter = nil
    }

    func hasHeldWork() -> Bool { waiter != nil || observer != nil }

    func count() -> Int { calls.count }

    func subscribe(
        requirementID: String,
        grant        : Grant
    ) async throws -> UUID {
        Issue.record("Unexpected subscription")
        throw CancellationError()
    }

    func unsubscribe(subscriptionID: UUID) async throws {
        Issue.record("Unexpected unsubscribe")
        throw CancellationError()
    }
}
