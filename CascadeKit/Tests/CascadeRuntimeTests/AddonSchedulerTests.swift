//
//  AddonSchedulerTests.swift
//  Cascade
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeRuntime

@Suite struct AddonSchedulerTests {
    let owner: AddonID

    init() throws {
        owner = try #require(AddonID(rawValue: "com.example.scheduler"))
    }
    let wall = Date(timeIntervalSince1970: 2_000_000_000)

    func publication(owner: AddonID? = nil) -> PublicationID {
        PublicationID(addonID: owner ?? self.owner, instanceID: UUID(), sessionID: UUID())
    }

    func action() throws -> ActionRequest {
        try ActionRequest(
            schemaVersion: 1, requestID: UUID(), publicationID: publication(), actionID: "pause", input: Data(),
            deadline: wall.addingTimeInterval(30), observedRevision: 1)
    }

    @Test func oneJobPerOwnerAndTwoGlobalKeepThirdOwnerWaiting() throws {
        var scheduler = AddonScheduler()
        let second = try #require(AddonID(rawValue: "com.example.second"))
        let third = try #require(AddonID(rawValue: "com.example.third"))
        let now = RuntimeInstant(wall: wall, monotonic: .zero)
        let firstID = try scheduler.enqueue(.refresh(publication()), owner: owner, deadline: .seconds(20), at: now)
        _ = try scheduler.enqueue(.refresh(publication()), owner: owner, deadline: .seconds(20), at: now)
        _ = try scheduler.enqueue(.refresh(publication(owner: second)), owner: second, deadline: .seconds(20), at: now)
        let thirdID = try scheduler.enqueue(
            .refresh(publication(owner: third)), owner: third, deadline: .seconds(20), at: now)
        #expect(scheduler.takeReady(at: .zero)?.id == firstID)
        #expect(scheduler.takeReady(at: .zero)?.owner == second)
        #expect(scheduler.takeReady(at: .zero) == nil)
        try scheduler.finish(firstID, owner: owner)
        #expect(scheduler.takeReady(at: .zero)?.owner == owner)
        #expect(scheduler.job(thirdID)?.phase == .queued)
    }

    @Test func refreshFloodCoalescesWithoutPostponingDeadlineOrQueueAge() throws {
        var scheduler = AddonScheduler(maximumRetainedBytes: 8_192)
        let id = publication()
        let first = try scheduler.enqueue(
            .refresh(id), owner: owner, deadline: .seconds(10), at: RuntimeInstant(wall: wall, monotonic: .zero))
        for _ in 0..<100 {
            #expect(
                try scheduler.enqueue(
                    .refresh(id), owner: owner, deadline: .seconds(20),
                    at: RuntimeInstant(wall: wall, monotonic: .seconds(1))) == first)
        }
        #expect(scheduler.count == 1)
        #expect(scheduler.job(first)?.deadline == .seconds(10))
        #expect(scheduler.retainedBytes <= 8_192)
        #expect(scheduler.expire(at: .seconds(10)).map(\.job.id) == [first])
        #expect(scheduler.retainedBytes == 0)
    }

    @Test func commandsHavePriorityUntilOldRefreshNeedsService() throws {
        var scheduler = AddonScheduler()
        let refresh = try scheduler.enqueue(
            .refresh(publication()), owner: owner, deadline: .seconds(30),
            at: RuntimeInstant(wall: wall, monotonic: .zero))
        let command = try scheduler.enqueue(
            .command(action()), owner: owner, deadline: .seconds(30),
            at: RuntimeInstant(wall: wall, monotonic: .seconds(1)))
        #expect(scheduler.takeReady(at: .seconds(1))?.id == command)
        try scheduler.finish(command, owner: owner)
        _ = try scheduler.enqueue(
            .command(action()), owner: owner, deadline: .seconds(30),
            at: RuntimeInstant(wall: wall, monotonic: .seconds(6)))
        #expect(scheduler.takeReady(at: .seconds(6))?.id == refresh)
    }

    @Test func fifthPendingCommandIsRejectedWithoutDroppingEarlierCommands() throws {
        var scheduler = AddonScheduler()
        let now = RuntimeInstant(wall: wall, monotonic: .zero)
        let request = try action()
        let first = try scheduler.enqueue(.command(request), owner: owner, deadline: .seconds(20), at: now)
        #expect(try scheduler.enqueue(.command(request), owner: owner, deadline: .seconds(20), at: now) == first)
        for _ in 0..<3 { _ = try scheduler.enqueue(.command(action()), owner: owner, deadline: .seconds(20), at: now) }
        #expect(throws: AddonFailure.self) {
            try scheduler.enqueue(.command(action()), owner: owner, deadline: .seconds(20), at: now)
        }
        #expect(scheduler.count == 4)
        #expect(scheduler.takeReady(at: .zero)?.id == first)
    }

    @Test func runningTimeoutKeepsCapacityUntilActualFinishAndEmitsStopOnce() throws {
        var scheduler = AddonScheduler()
        let now = RuntimeInstant(wall: wall, monotonic: .zero)
        let running = try scheduler.enqueue(.refresh(publication()), owner: owner, deadline: .seconds(5), at: now)
        let waiting = try scheduler.enqueue(.command(action()), owner: owner, deadline: .seconds(20), at: now)
        _ = scheduler.takeReady(at: .seconds(5 - 1))  // Command priority selects waiting first.
        try scheduler.finish(waiting, owner: owner)
        #expect(scheduler.takeReady(at: .seconds(4))?.id == running)
        let expired = scheduler.expire(at: .seconds(5))
        #expect(expired.map(\.job.id) == [running])
        #expect(expired.first?.requiresStop == true)
        #expect(scheduler.expire(at: .seconds(6)).isEmpty)
        let next = try scheduler.enqueue(
            .refresh(publication()), owner: owner, deadline: .seconds(20),
            at: RuntimeInstant(wall: wall, monotonic: .seconds(6)))
        #expect(scheduler.takeReady(at: .seconds(6)) == nil)
        try scheduler.finish(running, owner: owner)
        #expect(scheduler.takeReady(at: .seconds(6))?.id == next)
    }

    @Test func cancellationRemovesPendingWorkAndLateFinishCannotFreeAnotherJob() throws {
        var scheduler = AddonScheduler()
        let now = RuntimeInstant(wall: wall, monotonic: .zero)
        let running = try scheduler.enqueue(.refresh(publication()), owner: owner, deadline: .seconds(20), at: now)
        _ = scheduler.takeReady(at: .zero)
        _ = try scheduler.enqueue(.command(action()), owner: owner, deadline: .seconds(20), at: now)
        let cancelled = scheduler.cancel(owner: owner)
        #expect(cancelled.count == 2)
        #expect(scheduler.count == 1)
        #expect(scheduler.takeReady(at: .zero) == nil)
        try scheduler.finish(running, owner: owner)
        let next = try scheduler.enqueue(.refresh(publication()), owner: owner, deadline: .seconds(20), at: now)
        _ = scheduler.takeReady(at: .zero)
        try scheduler.finish(running, owner: owner)
        #expect(scheduler.job(next)?.phase == .running)
        #expect(scheduler.runningCount == 1)
    }

    @Test func foreignOwnerCannotEnqueueOrFinishAndExpiredQueueReportsRejection() throws {
        var scheduler = AddonScheduler()
        let foreign = try #require(AddonID(rawValue: "com.example.foreign"))
        let now = RuntimeInstant(wall: wall, monotonic: .zero)
        #expect(throws: AddonFailure.self) {
            try scheduler.enqueue(.refresh(publication()), owner: foreign, deadline: .seconds(20), at: now)
        }
        let id = try scheduler.enqueue(.command(action()), owner: owner, deadline: .seconds(5), at: now)
        #expect(scheduler.takeReady(at: .seconds(5)) == nil)
        #expect(scheduler.expire(at: .seconds(5)).first?.requiresStop == false)
        #expect(scheduler.count == 0)
        let current = try scheduler.enqueue(.refresh(publication()), owner: owner, deadline: .seconds(20), at: now)
        _ = scheduler.takeReady(at: .zero)
        #expect(throws: AddonFailure.self) { try scheduler.finish(current, owner: foreign) }
        #expect(scheduler.runningCount == 1)
        #expect(scheduler.job(id) == nil)
    }

    @Test func runningRefreshAcceptsOneFollowupAndGlobalByteLimitIsTransactional() throws {
        var scheduler = AddonScheduler(maximumRetainedBytes: 16_384)
        let now = RuntimeInstant(wall: wall, monotonic: .zero)
        let publication = publication()
        let first = try scheduler.enqueue(.refresh(publication), owner: owner, deadline: .seconds(20), at: now)
        _ = scheduler.takeReady(at: .zero)
        let followup = try scheduler.enqueue(.refresh(publication), owner: owner, deadline: .seconds(20), at: now)
        #expect(first != followup)
        #expect(try scheduler.enqueue(.refresh(publication), owner: owner, deadline: .seconds(20), at: now) == followup)
        #expect(throws: AddonFailure.self) {
            try scheduler.enqueue(.command(action()), owner: owner, deadline: .seconds(20), at: now)
        }
        #expect(scheduler.count == 2)
        try scheduler.finish(first, owner: owner)
        #expect(scheduler.takeReady(at: .zero)?.id == followup)
    }

    @Test func changedCommandCannotReplaceQueuedInputAndStoppingDisarmsDeadline() throws {
        var scheduler = AddonScheduler()
        let now = RuntimeInstant(wall: wall, monotonic: .zero)
        let request = try action()
        let id = try scheduler.enqueue(.command(request), owner: owner, deadline: .seconds(20), at: now)
        let changed = try ActionRequest(
            schemaVersion: 1, requestID: request.requestID, publicationID: request.publicationID,
            actionID: request.actionID, input: Data([1]), deadline: request.deadline,
            observedRevision: request.observedRevision)
        #expect(throws: AddonFailure.self) {
            try scheduler.enqueue(.command(changed), owner: owner, deadline: .seconds(20), at: now)
        }
        #expect(scheduler.job(id)?.work == .command(request))
        #expect(scheduler.nextDeadline == .seconds(20))
        _ = scheduler.takeReady(at: .zero)
        _ = scheduler.expire(at: .seconds(20))
        #expect(scheduler.nextDeadline == nil)
        #expect(scheduler.runningCount == 1)
    }

    @Test func admittedCommandKeepsMonotonicDeadlineAcrossCivilClockChanges() throws {
        for shift: TimeInterval in [-3_600, 3_600] {
            var journal = ActionJournal()
            var scheduler = AddonScheduler()
            let request = try action()
            _ = try journal.admit(request, owner: owner, at: RuntimeInstant(wall: wall, monotonic: .seconds(100)))
            let deadline = try #require(journal.nextDeadline)
            let ticket = try scheduler.enqueue(
                .command(request), owner: owner, deadline: deadline,
                at: RuntimeInstant(wall: wall.addingTimeInterval(shift), monotonic: .seconds(101)))
            #expect(scheduler.job(ticket)?.deadline == .seconds(130))
            #expect(scheduler.takeReady(at: .seconds(102))?.id == ticket)
            #expect(scheduler.expire(at: .seconds(130)).first?.requiresStop == true)
        }
    }

}
