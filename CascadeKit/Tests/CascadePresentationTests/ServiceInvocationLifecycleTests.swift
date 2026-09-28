//
//  ServiceInvocationLifecycleTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeAddonSDK

/// ServiceInvocationLifecycleTests uses empty caller-owned buffers to keep this scalar
/// transition suite independent of runtime accounting.
@Suite
struct ServiceInvocationLifecycleTests {
    private typealias Lifecycle = ServiceInvocationLifecycle
    private func invocation(id: UUID = UUID(), operation: String = "read") throws
        -> ServiceInvocation
    {
        try ServiceInvocation(
            schemaVersion: 1,
            requestID: id,
            contractID: "example.service",
            operation: operation,
            payload: Data(),
            deadline: Date(timeIntervalSince1970: 2_000_000_000)
        )
    }
    private func completion(
        _ request: ServiceInvocation,
        id: UUID? = nil,
        contract: String? = nil,
        operation: String? = nil
    ) throws -> InvocationCompletion {
        .service(
            requestID: id ?? request.requestID,
            response: try ServiceResponse(
                schemaVersion: 1,
                contractID: contract ?? request.contractID,
                operation: operation ?? request.operation,
                payload: Data()
            )
        )
    }
    private func expectFailure(_ code: AddonFailure.Code, _ body: () throws -> Void) {
        do {
            try body()
            Issue.record("Expected lifecycle refusal \(code)")
        } catch { #expect((error as? AddonFailure)?.code == code) }
    }

    @Test
    func admissionKeepsOnePendingAndBindsGrantMetadata() throws {
        let generation = ConnectionGeneration()
        let grant = UUID()
        let ledger = Lifecycle(generation: generation)
        let request = try invocation()
        let ticket = try ledger.begin(request, grantID: grant)
        #expect(
            ticket.generation == generation && ticket.grantID == grant
                && ticket.requestID == request.requestID
        )
        #expect(ticket.contractID == "example.service" && ticket.operation == "read")
        expectFailure(.resourceDenied) { _ = try ledger.begin(request, grantID: UUID()) }
        #expect(ledger.cancel(ticket) == .init(ticket: ticket, failure: .cancelled))
        #expect(try ledger.begin(request, grantID: grant) != ticket)
    }

    @Test
    func foreignAndObsoleteTicketsCannotRetireCurrentWork() throws {
        let generation = ConnectionGeneration()
        let grant = UUID()
        let request = try invocation()
        let ledger = Lifecycle(generation: generation)
        let other = Lifecycle(generation: generation)
        let old = try ledger.begin(request, grantID: grant)
        let foreign = try other.begin(request, grantID: grant)
        #expect(old != foreign)
        expectFailure(.sessionRevoked) { try ledger.beginHandoff(foreign) }
        #expect(ledger.cancel(foreign) == nil)
        #expect(ledger.observeHandoff(.rejectedBeforeHandoff, ticket: foreign) == nil)
        try ledger.beginHandoff(old)
        expectFailure(.sessionRevoked) {
            _ = try ledger.consume(completion(request), ticket: foreign, generation: generation)
        }
        #expect(
            try ledger.consume(completion(request), ticket: old, generation: generation) == .deliver
        )
        let fresh = try ledger.begin(request, grantID: grant)
        #expect(fresh != old && fresh.requestID == old.requestID)
        try ledger.beginHandoff(fresh)
        #expect(ledger.cancel(old) == nil)
        #expect(ledger.observeHandoff(.accepted, ticket: old) == nil)
        #expect(ledger.observeHandoff(.rejectedBeforeHandoff, ticket: old) == nil)
        expectFailure(.sessionRevoked) {
            _ = try ledger.consume(completion(request), ticket: old, generation: generation)
        }
        #expect(
            try ledger.consume(completion(request), ticket: fresh, generation: generation)
                == .deliver
        )
    }

    @Test(arguments: ["generation", "requestID", "contract", "operation", "kind"], [false, true])
    func invalidCorrelationLeavesCapacityOccupied(_ mismatch: String, _ cancelled: Bool) throws {
        let generation = ConnectionGeneration()
        let ledger = Lifecycle(generation: generation)
        let request = try invocation()
        let ticket = try ledger.begin(request, grantID: UUID())
        try ledger.beginHandoff(ticket)
        if cancelled { #expect(ledger.cancel(ticket)?.failure == .outcomeUnknown) }
        let wrong: InvocationCompletion =
            mismatch == "kind"
            ? .action(requestID: request.requestID, outcome: .completed(payload: Data()))
            : try completion(
                request,
                id: mismatch == "requestID" ? UUID() : nil,
                contract: mismatch == "contract" ? "other.service" : nil,
                operation: mismatch == "operation" ? "write" : nil
            )
        expectFailure(mismatch == "generation" ? .sessionRevoked : .invalidPayload) {
            _ = try ledger.consume(
                wrong,
                ticket: ticket,
                generation: mismatch == "generation" ? ConnectionGeneration() : generation
            )
        }
        expectFailure(.resourceDenied) { _ = try ledger.begin(request, grantID: UUID()) }
        #expect(
            try ledger.consume(completion(request), ticket: ticket, generation: generation)
                == (cancelled ? .discardCancelled : .deliver)
        )
        expectFailure(.sessionRevoked) {
            _ = try ledger.consume(completion(request), ticket: ticket, generation: generation)
        }
    }

    @Test
    func preparedReplyAndDuplicateHandoffLeaveWorkIntact() throws {
        let generation = ConnectionGeneration()
        let ledger = Lifecycle(generation: generation)
        let request = try invocation()
        let ticket = try ledger.begin(request, grantID: UUID())
        #expect(ledger.observeHandoff(.accepted, ticket: ticket) == nil)
        #expect(ledger.observeHandoff(.rejectedBeforeHandoff, ticket: ticket) == nil)
        expectFailure(.invalidPayload) {
            _ = try ledger.consume(completion(request), ticket: ticket, generation: generation)
        }
        try ledger.beginHandoff(ticket)
        expectFailure(.invalidPayload) { try ledger.beginHandoff(ticket) }
        #expect(ledger.observeHandoff(.accepted, ticket: ticket) == nil)
        expectFailure(.invalidPayload) { try ledger.beginHandoff(ticket) }
        // Accepted exposure cannot subsequently be described as a request-side rejection.
        #expect(ledger.observeHandoff(.rejectedBeforeHandoff, ticket: ticket) == nil)
        #expect(
            try ledger.consume(completion(request), ticket: ticket, generation: generation)
                == .deliver
        )
    }

    @Test
    func replyBeforeAcceptanceWinsAndSurvivesLateObservation() throws {
        let generation = ConnectionGeneration()
        let ledger = Lifecycle(generation: generation)
        let request = try invocation()
        let ticket = try ledger.begin(request, grantID: UUID())
        try ledger.beginHandoff(ticket)
        #expect(
            try ledger.consume(completion(request), ticket: ticket, generation: generation)
                == .deliver
        )
        #expect(ledger.observeHandoff(.accepted, ticket: ticket) == nil)
        #expect(ledger.observeHandoff(.rejectedBeforeHandoff, ticket: ticket) == nil)
        #expect(ledger.cancel(ticket) == nil && ledger.close() == nil)
    }

    @Test
    func provenRejectionIsNotSentAndCompletesOnlyOnce() throws {
        let ledger = Lifecycle(generation: ConnectionGeneration())
        let request = try invocation()
        let ticket = try ledger.begin(request, grantID: UUID())
        try ledger.beginHandoff(ticket)
        #expect(
            ledger.observeHandoff(.rejectedBeforeHandoff, ticket: ticket)
                == .init(ticket: ticket, failure: .notSent)
        )
        #expect(ledger.observeHandoff(.rejectedBeforeHandoff, ticket: ticket) == nil)
        #expect(ledger.cancel(ticket) == nil && ledger.close() == nil)
    }

    @Test
    func cancellationBeforeExposureRetiresOnlyThatTicket() throws {
        let ledger = Lifecycle(generation: ConnectionGeneration())
        let request = try invocation()
        let ticket = try ledger.begin(request, grantID: UUID())
        #expect(ledger.cancel(ticket) == .init(ticket: ticket, failure: .cancelled))
        #expect(ledger.cancel(ticket) == nil)
        expectFailure(.sessionRevoked) { try ledger.beginHandoff(ticket) }
        #expect(ledger.observeHandoff(.accepted, ticket: ticket) == nil)
        #expect(try ledger.begin(request, grantID: UUID()) != ticket)
    }

    @Test(arguments: ["read", "write", "custom"], [false, true])
    func everyExposedOperationRemainsUnknownUntilExactReply(_ operation: String, _ accepted: Bool)
        throws
    {
        let generation = ConnectionGeneration()
        let ledger = Lifecycle(generation: generation)
        let request = try invocation(operation: operation)
        let ticket = try ledger.begin(request, grantID: UUID())
        try ledger.beginHandoff(ticket)
        if accepted { #expect(ledger.observeHandoff(.accepted, ticket: ticket) == nil) }
        #expect(ledger.cancel(ticket) == .init(ticket: ticket, failure: .outcomeUnknown))
        #expect(ledger.cancel(ticket) == nil)
        expectFailure(.resourceDenied) { _ = try ledger.begin(request, grantID: UUID()) }
        #expect(
            try ledger.consume(completion(request), ticket: ticket, generation: generation)
                == .discardCancelled
        )
        #expect(ledger.cancel(ticket) == nil && ledger.close() == nil)
    }

    @Test(arguments: [false, true])
    func cancellationBeforeObservationDoesNotRewriteUnknown(_ accepted: Bool) throws {
        let generation = ConnectionGeneration()
        let ledger = Lifecycle(generation: generation)
        let request = try invocation()
        let ticket = try ledger.begin(request, grantID: UUID())
        try ledger.beginHandoff(ticket)
        #expect(ledger.cancel(ticket)?.failure == .outcomeUnknown)
        #expect(
            ledger.observeHandoff(accepted ? .accepted : .rejectedBeforeHandoff, ticket: ticket)
                == nil
        )
        if accepted {
            expectFailure(.resourceDenied) { _ = try ledger.begin(request, grantID: UUID()) }
            #expect(
                try ledger.consume(completion(request), ticket: ticket, generation: generation)
                    == .discardCancelled
            )
        }
        #expect(try ledger.begin(request, grantID: UUID()) != ticket)
    }

    @Test
    func genericSendErrorIsNotEvidenceOfNonExposure() throws {
        let ledger = Lifecycle(generation: ConnectionGeneration())
        let request = try invocation()
        let ticket = try ledger.begin(request, grantID: UUID())
        try ledger.beginHandoff(ticket)
        // A future transport catches this error without fabricating rejectedBeforeHandoff.
        do { throw AddonFailure(code: .dependencyUnavailable, reason: "Transport failed") } catch {
            #expect((error as? AddonFailure)?.code == .dependencyUnavailable)
        }
        expectFailure(.resourceDenied) { _ = try ledger.begin(request, grantID: UUID()) }
        #expect(ledger.close() == .init(ticket: ticket, failure: .outcomeUnknown))
    }

    @Test(arguments: ["read", "write", "custom"], [0, 1, 2])
    func closePermanentlyRevokesEveryPhase(_ operation: String, _ phase: Int) throws {
        let generation = ConnectionGeneration()
        let ledger = Lifecycle(generation: generation)
        let request = try invocation(operation: operation)
        let ticket = try ledger.begin(request, grantID: UUID())
        if phase > 0 { try ledger.beginHandoff(ticket) }
        if phase == 2 { #expect(ledger.observeHandoff(.accepted, ticket: ticket) == nil) }
        #expect(
            ledger.close() == .init(ticket: ticket, failure: phase == 0 ? .closed : .outcomeUnknown)
        )
        #expect(ledger.close() == nil && ledger.cancel(ticket) == nil)
        #expect(ledger.observeHandoff(.accepted, ticket: ticket) == nil)
        #expect(ledger.observeHandoff(.rejectedBeforeHandoff, ticket: ticket) == nil)
        expectFailure(.sessionRevoked) { _ = try ledger.begin(request, grantID: UUID()) }
        expectFailure(.sessionRevoked) { try ledger.beginHandoff(ticket) }
        expectFailure(.sessionRevoked) {
            _ = try ledger.consume(completion(request), ticket: ticket, generation: generation)
        }
    }

    @Test(arguments: [0, 1, 2])
    func closeAfterCancellationCannotCompleteAgain(_ phase: Int) throws {
        let ledger = Lifecycle(generation: ConnectionGeneration())
        let request = try invocation()
        let ticket = try ledger.begin(request, grantID: UUID())
        if phase > 0 { try ledger.beginHandoff(ticket) }
        if phase == 2 { #expect(ledger.observeHandoff(.accepted, ticket: ticket) == nil) }
        #expect(ledger.cancel(ticket) != nil)
        #expect(ledger.close() == nil && ledger.close() == nil)
    }

    @Test
    func idleCloseAndFreshGenerationAreIndependent() throws {
        let oldGeneration = ConnectionGeneration()
        let freshGeneration = ConnectionGeneration()
        let old = Lifecycle(generation: oldGeneration)
        let fresh = Lifecycle(generation: freshGeneration)
        let request = try invocation()
        let oldTicket = try old.begin(request, grantID: UUID())
        #expect(old.close()?.failure == .closed)
        let ticket = try fresh.begin(request, grantID: UUID())
        try fresh.beginHandoff(ticket)
        expectFailure(.sessionRevoked) {
            _ = try fresh.consume(completion(request), ticket: oldTicket, generation: oldGeneration)
        }
        #expect(
            try fresh.consume(completion(request), ticket: ticket, generation: freshGeneration)
                == .deliver
        )
        #expect(fresh.close() == nil && fresh.close() == nil)
        expectFailure(.sessionRevoked) { _ = try fresh.begin(request, grantID: UUID()) }
    }
}
