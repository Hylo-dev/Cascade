//
//  ActionJournalTests.swift
//  Cascade
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeRuntime

@Suite struct ActionJournalTests {
    let owner: AddonID

    init() throws {
        owner = try #require(AddonID(rawValue: "com.example.actions"))
    }
    let wall = Date(timeIntervalSince1970: 2_000_000_000)

    func request(id: UUID = UUID(), input: Data = Data()) throws -> ActionRequest {
        try ActionRequest(
            schemaVersion: 1,
            requestID: id,
            publicationID: PublicationID(addonID: owner, instanceID: UUID(), sessionID: UUID()),
            actionID: "pause",
            input: input,
            deadline: wall.addingTimeInterval(20),
            observedRevision: 1
        )
    }

    @Test func duplicateRequestRetainsOneEntryAndRejectsChangedContent() throws {
        var journal = ActionJournal()
        let action = try request()
        let now = RuntimeInstant(wall: wall, monotonic: .zero)
        #expect(try journal.admit(action, owner: owner, at: now) == .admitted)
        #expect(try journal.admit(action, owner: owner, at: now) == .duplicate(.queued))
        let bytes = journal.retainedBytes
        let collision = try request(id: action.requestID, input: Data([1]))
        #expect(throws: AddonFailure.self) { try journal.admit(collision, owner: owner, at: now) }
        #expect(journal.retainedBytes == bytes)
        #expect(journal.count == 1)
    }

    @Test func acknowledgementDoesNotCompleteCommandAndLostReplyIsUnknown() throws {
        var journal = ActionJournal()
        let action = try request()
        let generation = ConnectionGeneration()
        _ = try journal.admit(action, owner: owner, at: RuntimeInstant(wall: wall, monotonic: .zero))
        try journal.markSent(action.requestID, owner: owner, generation: generation, at: .seconds(1))
        #expect(journal.acknowledge(action.requestID, owner: owner, generation: generation, at: .seconds(2)) == true)
        #expect(journal.state(action.requestID, owner: owner) == .acknowledged(generation))
        journal.connectionLost(owner: owner, generation: generation)
        #expect(journal.state(action.requestID, owner: owner) == .finished(.outcomeUnknown))
        #expect(
            try journal.admit(action, owner: owner, at: RuntimeInstant(wall: wall, monotonic: .seconds(3)))
                == .duplicate(.finished(.outcomeUnknown)))
    }

    @Test func oldGenerationAndForeignOwnerCannotFinishCurrentCommand() throws {
        var journal = ActionJournal()
        let action = try request()
        let current = ConnectionGeneration()
        let foreign = try #require(AddonID(rawValue: "com.example.foreign"))
        _ = try journal.admit(action, owner: owner, at: RuntimeInstant(wall: wall, monotonic: .zero))
        try journal.markSent(action.requestID, owner: owner, generation: current, at: .zero)
        #expect(
            try !journal.complete(
                action.requestID, owner: owner, generation: ConnectionGeneration(),
                outcome: .completed(payload: Data()), at: .seconds(1)))
        #expect(
            try !journal.complete(
                action.requestID, owner: foreign, generation: current, outcome: .completed(payload: Data()),
                at: .seconds(1)))
        #expect(journal.state(action.requestID, owner: owner) == .sent(current))
        #expect(
            try journal.complete(
                action.requestID, owner: owner, generation: current, outcome: .completed(payload: Data([7])),
                at: .seconds(1)) == true)
        #expect(
            try !journal.complete(
                action.requestID, owner: owner, generation: current, outcome: .completed(payload: Data([9])),
                at: .seconds(2)))
        #expect(journal.state(action.requestID, owner: owner) == .finished(.completed(payload: Data([7]))))
    }

    @Test func timeoutIsMonotonicAndLateOutcomeCannotReplaceUnknown() throws {
        var journal = ActionJournal()
        let action = try request()
        let generation = ConnectionGeneration()
        _ = try journal.admit(action, owner: owner, at: RuntimeInstant(wall: wall, monotonic: .seconds(100)))
        try journal.markSent(action.requestID, owner: owner, generation: generation, at: .seconds(101))
        // A backward civil-clock jump must not renew an already admitted command.
        _ = try journal.admit(
            action, owner: owner, at: RuntimeInstant(wall: wall.addingTimeInterval(-3_600), monotonic: .seconds(119)))
        journal.expire(at: .seconds(120))
        #expect(journal.state(action.requestID, owner: owner) == .finished(.outcomeUnknown))
        #expect(
            try !journal.complete(
                action.requestID, owner: owner, generation: generation, outcome: .completed(payload: Data()),
                at: .seconds(121)))
    }

    @Test func unsentTimeoutIsRejectedAndCannotBeMarkedSent() throws {
        var journal = ActionJournal()
        let action = try request()
        _ = try journal.admit(action, owner: owner, at: RuntimeInstant(wall: wall, monotonic: .zero))
        #expect(throws: AddonFailure.self) {
            try journal.markSent(action.requestID, owner: owner, generation: ConnectionGeneration(), at: .seconds(20))
        }
        guard case .finished(.rejected(let failure)) = journal.state(action.requestID, owner: owner) else {
            Issue.record("Unsent expired command must have a definite rejection")
            return
        }
        #expect(failure.code == .deadlineExceeded)
    }

    @Test func resultSpaceIsReservedBeforeAdmissionAndReleasedAfterRetention() throws {
        var journal = ActionJournal(maximumRetainedBytes: 72 * 1_024)
        let action = try request(input: Data(repeating: 1, count: 4_096))
        let generation = ConnectionGeneration()
        _ = try journal.admit(action, owner: owner, at: RuntimeInstant(wall: wall, monotonic: .zero))
        #expect(throws: AddonFailure.self) {
            try journal.admit(request(), owner: owner, at: RuntimeInstant(wall: wall, monotonic: .zero))
        }
        try journal.markSent(action.requestID, owner: owner, generation: generation, at: .zero)
        #expect(
            try journal.complete(
                action.requestID, owner: owner, generation: generation,
                outcome: .completed(payload: Data(repeating: 2, count: 65_536)), at: .seconds(1)) == true)
        #expect(journal.retainedBytes <= 72 * 1_024)
        journal.expire(at: .seconds(600))
        #expect(journal.count == 0)
        #expect(journal.retainedBytes == 0)
    }

    @Test func retentionQuotaRejectsNewRequestsWithoutEvictingKnownOutcomes() throws {
        var journal = ActionJournal()
        var first: ActionRequest?
        for _ in 0..<128 {
            let action = try request()
            if first == nil { first = action }
            _ = try journal.admit(action, owner: owner, at: RuntimeInstant(wall: wall, monotonic: .zero))
            journal.cancel(owner: owner)
        }
        #expect(throws: AddonFailure.self) {
            try journal.admit(request(), owner: owner, at: RuntimeInstant(wall: wall, monotonic: .zero))
        }
        let retained = try #require(first)
        #expect(journal.state(retained.requestID, owner: owner) != nil)
        _ = try journal.admit(retained, owner: owner, at: RuntimeInstant(wall: wall, monotonic: .seconds(599)))
        journal.expire(at: .seconds(600))
        #expect(journal.count == 0)
    }

    @Test func cancellationPreservesUncertainEffectsAndRejectsUnsentCommands() throws {
        var journal = ActionJournal()
        let sent = try request()
        let queued = try request()
        let generation = ConnectionGeneration()
        let instant = RuntimeInstant(wall: wall, monotonic: .zero)
        _ = try journal.admit(sent, owner: owner, at: instant)
        _ = try journal.admit(queued, owner: owner, at: instant)
        try journal.markSent(sent.requestID, owner: owner, generation: generation, at: .zero)
        journal.cancel(owner: owner)
        #expect(journal.state(sent.requestID, owner: owner) == .finished(.outcomeUnknown))
        guard case .finished(.rejected(let failure)) = journal.state(queued.requestID, owner: owner) else {
            Issue.record("Queued command must be cancelled without pretending it was sent")
            return
        }
        #expect(failure.code == .sessionRevoked)
        #expect(
            try !journal.complete(
                sent.requestID, owner: owner, generation: generation, outcome: .completed(payload: Data()),
                at: .seconds(1)))
    }

    @Test func malformedOutcomeCannotConsumeTheOnlyCompletion() throws {
        var journal = ActionJournal()
        let action = try request()
        let generation = ConnectionGeneration()
        _ = try journal.admit(action, owner: owner, at: RuntimeInstant(wall: wall, monotonic: .zero))
        try journal.markSent(action.requestID, owner: owner, generation: generation, at: .zero)
        #expect(throws: AddonFailure.self) {
            try journal.complete(
                action.requestID, owner: owner, generation: generation,
                outcome: .completed(payload: Data(count: 65_537)), at: .seconds(1))
        }
        #expect(journal.state(action.requestID, owner: owner) == .sent(generation))
        #expect(
            try journal.complete(
                action.requestID, owner: owner, generation: generation, outcome: .completed(payload: Data()),
                at: .seconds(1)) == true)
    }

    @Test func nextWakeMovesFromExecutionDeadlineToRetentionAndThenDisarms() throws {
        var journal = ActionJournal()
        let action = try request()
        let generation = ConnectionGeneration()
        _ = try journal.admit(action, owner: owner, at: RuntimeInstant(wall: wall, monotonic: .seconds(100)))
        #expect(journal.nextDeadline == .seconds(120))
        try journal.markSent(action.requestID, owner: owner, generation: generation, at: .seconds(101))
        _ = try journal.complete(
            action.requestID, owner: owner, generation: generation, outcome: .completed(payload: Data()),
            at: .seconds(102))
        #expect(journal.nextDeadline == .seconds(700))
        journal.expire(at: .seconds(700))
        #expect(journal.nextDeadline == nil)
    }

    @Test func foreignAdmissionAndExpiredInputLeaveJournalUnchanged() throws {
        var journal = ActionJournal()
        let foreign = try #require(AddonID(rawValue: "com.example.foreign"))
        let action = try request()
        #expect(throws: AddonFailure.self) {
            try journal.admit(action, owner: foreign, at: RuntimeInstant(wall: wall, monotonic: .zero))
        }
        #expect(throws: AddonFailure.self) {
            try journal.admit(
                action, owner: owner, at: RuntimeInstant(wall: wall.addingTimeInterval(30), monotonic: .zero))
        }
        #expect(journal.count == 0)
        #expect(journal.retainedBytes == 0)
    }

}
