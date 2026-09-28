//
//  StorageRequestLifecycleTests.swift
//  Cascade
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeAddonSDK

@Suite
struct StorageRequestLifecycleTests {
    private typealias Lifecycle = StorageRequestLifecycle

    private func request(
        _ operation: StorageOperation = .write,
        id         : UUID = UUID(),
        value      : Data = Data([7])
    ) throws -> StorageRequest {
        try StorageRequest(
            requestID: id,
            operation: operation,
            key      : "key",
            value    : operation == .write ? value : nil
        )
    }

    private func response(_ request: StorageRequest) throws -> StorageResponse {
        try StorageResponse(
            requestID: request.requestID,
            operation: request.operation,
            result   : request.operation == .read ? .missing : .acknowledged
        )
    }

    /// expectFailure checks exact bounded errors without accepting an unrelated thrown failure.
    private func expectFailure(
        _ code   : AddonFailure.Code,
        operation: () throws -> Void
    ) {
        do {
            try operation()
            Issue.record("Expected bounded lifecycle refusal")
        } catch let failure as AddonFailure { #expect(failure.code == code) } catch {
            Issue.record("Expected AddonFailure, got \(error)")
        }
    }

    @Test
    func foreignTicketCannotTransitionOrCancelCurrentRequest() throws {
        let generation = ConnectionGeneration()
        let first      = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let other = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request = try request()
        let ticket  = try first.begin(request)
        let foreign = try other.begin(request)
        #expect(ticket != foreign)
        expectFailure(.sessionRevoked) { try first.beginHandoff(foreign) }
        #expect(first.cancel(foreign) == nil)
        #expect(
            first.observeHandoff(
                .rejectedBeforeHandoff,
                ticket: foreign
            ) == nil
        )
        try first.beginHandoff(ticket)
        #expect(
            try first.consume(
                response(request),
                generation: generation,
                sequence  : ticket.sequence
            ) == .deliver
        )
    }

    @Test(arguments: ["generation", "sequence", "id", "operation"])
    func wrongResponseCorrelationPreservesPending(_ mismatch: String) throws {
        let generation = ConnectionGeneration()
        let lifecycle  = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request = try request()
        let ticket  = try lifecycle.begin(request)
        try lifecycle.beginHandoff(ticket)
        let wrong = try response(
            self.request(
                mismatch == "operation" ? .remove : .write,
                id: mismatch == "id" ? UUID() : request.requestID
            )
        )
        expectFailure(mismatch == "generation" ? .sessionRevoked : .invalidPayload) {
            _ = try lifecycle.consume(
                wrong,
                generation: mismatch == "generation" ? ConnectionGeneration() : generation,
                sequence  : ticket.sequence + (mismatch == "sequence" ? 1 : 0)
            )
        }
        #expect(
            try lifecycle.consume(
                response(request),
                generation: generation,
                sequence  : ticket.sequence
            ) == .deliver
        )
    }

    @Test
    func duplicateResponseAndLateObservationCannotAffectNewerPending() throws {
        let generation = ConnectionGeneration()
        let lifecycle  = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request = try request()
        let first   = try lifecycle.begin(request)
        try lifecycle.beginHandoff(first)
        let reply = try response(request)
        #expect(
            try lifecycle.consume(
                reply,
                generation: generation,
                sequence  : first.sequence
            ) == .deliver
        )
        expectFailure(.sessionRevoked) {
            _ = try lifecycle.consume(
                reply,
                generation: generation,
                sequence  : first.sequence
            )
        }
        let second = try lifecycle.begin(request)
        #expect(second.sequence == first.sequence + 1)
        #expect(second.requestID == first.requestID)
        #expect(second != first)
        #expect(
            lifecycle.observeHandoff(
                .accepted,
                ticket: first
            ) == nil
        )
        #expect(
            lifecycle.observeHandoff(
                .rejectedBeforeHandoff,
                ticket: first
            ) == nil
        )
        #expect(lifecycle.cancel(first) == nil)
        try lifecycle.beginHandoff(second)
        expectFailure(.invalidPayload) {
            _ = try lifecycle.consume(
                reply,
                generation: generation,
                sequence  : first.sequence
            )
        }
        #expect(
            try lifecycle.consume(
                reply,
                generation: generation,
                sequence  : second.sequence
            ) == .deliver
        )
    }

    @Test
    func beginKeepsOnePendingAndIssuesMonotonicTicketsAcrossGaps() throws {
        let generation = ConnectionGeneration()
        let lifecycle  = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request = try request(.remove)
        let first   = try lifecycle.begin(request)
        #expect(first.generation == generation)
        #expect(first.requestID == request.requestID)
        #expect(first.operation == .remove)
        #expect(first.sequence == 1)
        expectFailure(.resourceDenied) { _ = try lifecycle.begin(self.request()) }
        #expect(
            lifecycle.cancel(first)
                == .init(
                    ticket : first,
                    failure: .cancelled
                )
        )
        let second = try lifecycle.begin(request)
        #expect(second.sequence == 2)
        try lifecycle.beginHandoff(second)
        #expect(
            lifecycle.observeHandoff(
                .rejectedBeforeHandoff,
                ticket: second
            )
                == .init(
                    ticket : second,
                    failure: .notSent
                )
        )
        #expect(try lifecycle.begin(request).sequence == 3)
    }

    @Test
    func profileAndCheckedSequenceBoundariesUseExistingErrors() throws {
        expectFailure(.versionConflict) {
            _ = try Lifecycle(
                generation: ConnectionGeneration(),
                profile   : nil
            )
        }
        #expect(try Lifecycle.nextSequence(after: 0) == 1)
        #expect(try Lifecycle.nextSequence(after: UInt64.max - 1) == UInt64.max)
        expectFailure(.resourceDenied) { _ = try Lifecycle.nextSequence(after: UInt64.max) }
    }

    @Test
    func preparedResponseAndDuplicateHandoffDoNotRetireTicket() throws {
        let generation = ConnectionGeneration()
        let lifecycle  = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request = try request()
        let ticket  = try lifecycle.begin(request)
        #expect(
            lifecycle.observeHandoff(
                .accepted,
                ticket: ticket
            ) == nil
        )
        #expect(
            lifecycle.observeHandoff(
                .rejectedBeforeHandoff,
                ticket: ticket
            ) == nil
        )
        expectFailure(.invalidPayload) {
            _ = try lifecycle.consume(
                response(request),
                generation: generation,
                sequence  : ticket.sequence
            )
        }
        try lifecycle.beginHandoff(ticket)
        expectFailure(.invalidPayload) { try lifecycle.beginHandoff(ticket) }
        #expect(
            lifecycle.observeHandoff(
                .accepted,
                ticket: ticket
            ) == nil
        )
        expectFailure(.invalidPayload) { try lifecycle.beginHandoff(ticket) }
        #expect(
            lifecycle.observeHandoff(
                .rejectedBeforeHandoff,
                ticket: ticket
            ) == nil
        )
        #expect(
            try lifecycle.consume(
                response(request),
                generation: generation,
                sequence  : ticket.sequence
            ) == .deliver
        )
    }

    @Test
    func cancellationBeforeHandoffIsTerminalForThatTicket() throws {
        let lifecycle = try Lifecycle(
            generation: ConnectionGeneration(),
            profile   : .v1_1
        )
        let ticket = try lifecycle.begin(request())
        #expect(
            lifecycle.cancel(ticket)
                == .init(
                    ticket : ticket,
                    failure: .cancelled
                )
        )
        #expect(lifecycle.cancel(ticket) == nil)
        expectFailure(.sessionRevoked) { try lifecycle.beginHandoff(ticket) }
        #expect(
            lifecycle.observeHandoff(
                .accepted,
                ticket: ticket
            ) == nil
        )
        #expect(try lifecycle.begin(request()).sequence == 2)
    }

    @Test(
        arguments: [StorageOperation.read, .write, .remove],
        [false, true]
    )
    func inflightCancellationKeepsCapacityUntilExactReply(
        _ operation: StorageOperation,
        _ accepted : Bool
    ) throws {
        let generation = ConnectionGeneration()
        let lifecycle  = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request = try request(operation)
        let ticket  = try lifecycle.begin(request)
        try lifecycle.beginHandoff(ticket)
        if accepted {
            #expect(
                lifecycle.observeHandoff(
                    .accepted,
                    ticket: ticket
                ) == nil
            )
        }
        #expect(
            lifecycle.cancel(ticket)
                == .init(
                    ticket : ticket,
                    failure: operation == .read ? .cancelled : .outcomeUnknown
                )
        )
        #expect(lifecycle.cancel(ticket) == nil)
        expectFailure(.resourceDenied) { _ = try lifecycle.begin(self.request()) }
        #expect(
            try lifecycle.consume(
                response(request),
                generation: generation,
                sequence  : ticket.sequence
            ) == .discardCancelled
        )
        #expect(lifecycle.cancel(ticket) == nil)
        #expect(
            lifecycle.observeHandoff(
                .accepted,
                ticket: ticket
            ) == nil
        )
        #expect(try lifecycle.begin(self.request()).sequence == 2)
    }

    @Test(arguments: [false, true])
    func cancellationDuringAttemptHandlesLaterHandoffExactlyOnce(_ accepted: Bool) throws {
        let generation = ConnectionGeneration()
        let lifecycle  = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request = try request()
        let ticket  = try lifecycle.begin(request)
        try lifecycle.beginHandoff(ticket)
        #expect(
            lifecycle.cancel(ticket)
                == .init(
                    ticket : ticket,
                    failure: .outcomeUnknown
                )
        )
        #expect(
            lifecycle.observeHandoff(
                accepted ? .accepted : .rejectedBeforeHandoff,
                ticket: ticket
            ) == nil
        )
        if accepted {
            expectFailure(.resourceDenied) { _ = try lifecycle.begin(self.request()) }
            #expect(
                try lifecycle.consume(
                    response(request),
                    generation: generation,
                    sequence  : ticket.sequence
                ) == .discardCancelled
            )
        }
        #expect(lifecycle.cancel(ticket) == nil)
        #expect(try lifecycle.begin(self.request()).sequence == 2)
    }

    @Test
    func replyOrProvenRejectionBeforeCancellationReportsOnlyOnce() throws {
        let generation = ConnectionGeneration()
        let lifecycle  = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request = try request()
        let first   = try lifecycle.begin(request)
        try lifecycle.beginHandoff(first)
        #expect(
            lifecycle.observeHandoff(
                .rejectedBeforeHandoff,
                ticket: first
            )
                == .init(
                    ticket : first,
                    failure: .notSent
                )
        )
        #expect(lifecycle.cancel(first) == nil)
        #expect(
            lifecycle.observeHandoff(
                .rejectedBeforeHandoff,
                ticket: first
            ) == nil
        )
        let second = try lifecycle.begin(request)
        try lifecycle.beginHandoff(second)
        #expect(
            try lifecycle.consume(
                response(request),
                generation: generation,
                sequence  : second.sequence
            ) == .deliver
        )
        #expect(lifecycle.cancel(second) == nil)
        #expect(
            lifecycle.observeHandoff(
                .accepted,
                ticket: second
            ) == nil
        )
    }

    @Test(
        arguments: [StorageOperation.read, .write, .remove],
        [0, 1, 2]
    )
    func closeClassifiesPendingPhaseAndPermanentlyRevokes(
        _ operation: StorageOperation,
        _ phase    : Int
    ) throws {
        let generation = ConnectionGeneration()
        let lifecycle  = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request = try request(operation)
        let ticket  = try lifecycle.begin(request)
        if phase > 0 { try lifecycle.beginHandoff(ticket) }
        if phase == 2 {
            #expect(
                lifecycle.observeHandoff(
                    .accepted,
                    ticket: ticket
                ) == nil
            )
        }
        #expect(
            lifecycle.close()
                == .init(
                    ticket : ticket,
                    failure: phase == 0 || operation == .read ? .closed : .outcomeUnknown
                )
        )
        #expect(lifecycle.close() == nil)
        #expect(lifecycle.cancel(ticket) == nil)
        #expect(
            lifecycle.observeHandoff(
                .accepted,
                ticket: ticket
            ) == nil
        )
        #expect(
            lifecycle.observeHandoff(
                .rejectedBeforeHandoff,
                ticket: ticket
            ) == nil
        )
        expectFailure(.sessionRevoked) { _ = try lifecycle.begin(request) }
        expectFailure(.sessionRevoked) { try lifecycle.beginHandoff(ticket) }
        expectFailure(.sessionRevoked) {
            _ = try lifecycle.consume(
                response(request),
                generation: generation,
                sequence  : ticket.sequence
            )
        }
    }

    @Test(arguments: [StorageOperation.read, .write, .remove])
    func closeAfterLocalCancellationDoesNotCompleteCallerAgain(_ operation: StorageOperation) throws {
        let generation = ConnectionGeneration()
        let lifecycle  = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request = try request(operation)
        let ticket  = try lifecycle.begin(request)
        try lifecycle.beginHandoff(ticket)
        #expect(lifecycle.cancel(ticket) != nil)
        #expect(lifecycle.close() == nil)
        #expect(lifecycle.close() == nil)
        expectFailure(.sessionRevoked) {
            _ = try lifecycle.consume(
                response(request),
                generation: generation,
                sequence  : ticket.sequence
            )
        }
    }

    @Test
    func idleCloseAndFreshGenerationKeepInstancesSeparate() throws {
        let generation = ConnectionGeneration()
        let old        = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        #expect(old.close() == nil)
        #expect(old.close() == nil)
        expectFailure(.sessionRevoked) { _ = try old.begin(self.request()) }
        let oldOpen = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request         = try request()
        let oldTicket       = try oldOpen.begin(request)
        let freshGeneration = ConnectionGeneration()
        let fresh           = try Lifecycle(
            generation: freshGeneration,
            profile   : .v1_1
        )
        let freshTicket = try fresh.begin(request)
        #expect(freshTicket.sequence == 1)
        expectFailure(.sessionRevoked) { try fresh.beginHandoff(oldTicket) }
        try fresh.beginHandoff(freshTicket)
        expectFailure(.sessionRevoked) {
            _ = try fresh.consume(
                response(request),
                generation: generation,
                sequence  : oldTicket.sequence
            )
        }
        #expect(
            try fresh.consume(
                response(request),
                generation: freshGeneration,
                sequence  : freshTicket.sequence
            ) == .deliver
        )
    }

    @Test
    func codecFailureAndMaximumCallerOwnedValuesDoNotChangeCorrelation() throws {
        let generation = ConnectionGeneration()
        let lifecycle  = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let original = try StorageRequest(
            requestID: UUID(),
            operation: .write,
            key      : String(
                repeating: "é",
                count    : 128
            ),
            value: Data(
                repeating: 255,
                count    : 65_536
            )
        )
        let requestBytes = try StorageFrameCodec.encode(
            original,
            profile: .v1_1
        )
        let decoded = try StorageFrameCodec.decodeRequest(
            requestBytes,
            profile: .v1_1
        )
        let ticket = try lifecycle.begin(decoded)
        try lifecycle.beginHandoff(ticket)
        #expect(throws: (any Error).self) {
            try StorageFrameCodec.decodeResponse(
                Data("{}".utf8),
                profile: .v1_1
            )
        }
        let replyBytes = try StorageFrameCodec.encode(
            response(decoded),
            profile: .v1_1
        )
        #expect(
            try lifecycle.consume(
                StorageFrameCodec.decodeResponse(
                    replyBytes,
                    profile: .v1_1
                ),
                generation: generation,
                sequence  : ticket.sequence
            ) == .deliver
        )
        let read = try request(.read)
        let next = try lifecycle.begin(read)
        try lifecycle.beginHandoff(next)
        let response = try StorageResponse(
            requestID: read.requestID,
            operation: .read,
            result   : .value,
            value    : original.value
        )
        let raw = try StorageFrameCodec.encode(
            response,
            profile: .v1_1
        )
        let callerOwned = try StorageFrameCodec.decodeResponse(
            raw,
            profile: .v1_1
        )
        #expect(
            try lifecycle.consume(
                callerOwned,
                generation: generation,
                sequence  : next.sequence
            ) == .deliver
        )
        #expect(callerOwned.value == original.value)
    }

    @Test(arguments: [false, true])
    func missingAndPresentEmptyRemainDistinctCallerValues(_ present: Bool) throws {
        let generation = ConnectionGeneration()
        let lifecycle  = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request = try request(.read)
        let ticket  = try lifecycle.begin(request)
        try lifecycle.beginHandoff(ticket)
        let callerOwned = try StorageResponse(
            requestID: request.requestID,
            operation: .read,
            result   : present ? .value : .missing,
            value    : present ? Data() : nil
        )
        #expect(
            try lifecycle.consume(
                callerOwned,
                generation: generation,
                sequence  : ticket.sequence
            ) == .deliver
        )
        #expect(callerOwned.value == (present ? Data() : nil))
        #expect(callerOwned.result == (present ? .value : .missing))
    }

    @Test
    func failureResponseRemainsCallerOwnedWithoutAutomaticRetry() throws {
        let generation = ConnectionGeneration()
        let lifecycle  = try Lifecycle(
            generation: generation,
            profile   : .v1_1
        )
        let request = try request()
        let ticket  = try lifecycle.begin(request)
        try lifecycle.beginHandoff(ticket)
        let callerOwned = try StorageResponse(
            requestID    : request.requestID,
            operation    : .write,
            result       : .failure,
            failureCode  : .outcomeUnknown,
            failureReason: "The mutation outcome is unknown."
        )
        #expect(
            try lifecycle.consume(
                callerOwned,
                generation: generation,
                sequence  : ticket.sequence
            ) == .deliver
        )
        #expect(callerOwned.failureCode == .outcomeUnknown)
        #expect(lifecycle.close() == nil)
    }
}
