//
//  DeadlineQueueTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@testable import CascadeRuntime

@Suite struct DeadlineQueueTests {
    let owner: AddonID

    init() throws {
        owner = try #require(AddonID(rawValue: "com.example.deadlines"))
    }
    let wall = Date(timeIntervalSince1970: 2_000_000_000)

    @Test func civilClockJumpDoesNotExpireMonotonicWork() throws {
        var queue = DeadlineQueue()
        let civil = UUID()
        let elapsed = UUID()
        try queue.schedule(civil, owner: owner, deadline: .wall(wall.addingTimeInterval(60)))
        try queue.schedule(elapsed, owner: owner, deadline: .monotonic(.seconds(60)))
        let jumped = RuntimeInstant(wall: wall.addingTimeInterval(3_600), monotonic: .seconds(2))
        #expect(Set(try queue.drainDue(at: jumped).map(\.id)) == [civil])
        #expect(try queue.nextDelay(at: jumped) == .seconds(58))
        #expect(try queue.drainDue(at: jumped).isEmpty)
    }

    @Test func sleepDrainsEachDeadlineOnceWithoutReplayingMissedTicks() throws {
        var queue = DeadlineQueue()
        let first = UUID()
        let second = UUID()
        try queue.schedule(first, owner: owner, deadline: .monotonic(.seconds(10)))
        try queue.schedule(second, owner: owner, deadline: .wall(wall.addingTimeInterval(30)))
        let waking = RuntimeInstant(wall: wall.addingTimeInterval(600), monotonic: .seconds(600))
        #expect(Set(try queue.drainDue(at: waking).map(\.id)) == [first, second])
        #expect(try queue.nextDelay(at: waking) == nil)
        #expect(try queue.drainDue(at: waking).isEmpty)
        #expect(queue.retainedBytes == 0)
    }

    @Test func replacementRemainsBoundedAndEarlierDeadlineDisappears() throws {
        var queue = DeadlineQueue(maximumEntries: 1)
        let id = UUID()
        for second in 1...100 {
            try queue.schedule(id, owner: owner, deadline: .monotonic(.seconds(second)))
        }
        let now = RuntimeInstant(wall: wall, monotonic: .zero)
        #expect(queue.count == 1)
        #expect(try queue.nextDelay(at: now) == .seconds(100))
        #expect(throws: AddonFailure.self) { try queue.schedule(UUID(), owner: owner, deadline: .monotonic(.zero)) }
        #expect(try queue.nextDelay(at: now) == .seconds(100))
    }

    @Test func ownerRemovalClearsFutureEventsWithoutTouchingOtherOwners() throws {
        var queue = DeadlineQueue()
        let foreign = try #require(AddonID(rawValue: "com.example.foreign"))
        let owned = UUID()
        let other = UUID()
        try queue.schedule(owned, owner: owner, deadline: .monotonic(.seconds(10)))
        try queue.schedule(other, owner: foreign, deadline: .monotonic(.seconds(20)))
        #expect(throws: AddonFailure.self) { try queue.schedule(owned, owner: foreign, deadline: .monotonic(.zero)) }
        #expect(throws: AddonFailure.self) { try queue.cancel(owned, owner: foreign) }
        queue.remove(owner: owner)
        #expect(queue.count == 1)
        #expect(Set(try queue.drainDue(at: RuntimeInstant(wall: wall, monotonic: .seconds(100))).map(\.id)) == [other])
    }

    @Test func invalidDatesDoNotReplaceValidDeadlineAndDistantDatesAreBounded() throws {
        var queue = DeadlineQueue()
        let id = UUID()
        try queue.schedule(id, owner: owner, deadline: .monotonic(.seconds(10)))
        #expect(throws: AddonFailure.self) {
            try queue.schedule(id, owner: owner, deadline: .wall(Date(timeIntervalSince1970: .infinity)))
        }
        #expect(try queue.nextDelay(at: RuntimeInstant(wall: wall, monotonic: .zero)) == .seconds(10))
        try queue.cancel(id, owner: owner)
        try queue.schedule(
            id, owner: owner, deadline: .wall(Date(timeIntervalSince1970: Double.greatestFiniteMagnitude)))
        let delay = try #require(try queue.nextDelay(at: RuntimeInstant(wall: wall, monotonic: .zero)))
        #expect(delay > .zero)
        #expect(throws: AddonFailure.self) {
            try queue.drainDue(at: RuntimeInstant(wall: Date(timeIntervalSince1970: .nan), monotonic: .zero))
        }
        #expect(queue.count == 1)
    }
}
