//
//  ResourceGovernorTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct ResourceGovernorTests {

    let first  = AddonID(rawValue: "com.example.first")!
    let second = AddonID(rawValue: "com.example.second")!
    let third  = AddonID(rawValue: "com.example.third")!

    @Test
    func rejectedReservationChangesNoCounter() async throws {
        let governor = ResourceGovernor()
        _ = try await governor.admit(.asset(bytes: 8 * 1_024 * 1_024), owner: first)

        let bytes = await governor.usage(.retainedStateBytes)

        await #expect(throws: AddonFailure.self) { try await governor.admit(.asset(bytes: 1), owner: first) }

        #expect(await governor.usage(.assetBytes) == 8 * 1_024 * 1_024)
        #expect(await governor.usage(.retainedStateBytes) == bytes)
    }

    @Test
    func ownerCannotReleaseAnotherOwnersReservation() async throws {
        let governor = ResourceGovernor()
        let memory   = try await governor.admit(.temporaryMemory(bytes: 1_024), owner: first)

        await #expect(throws: AddonFailure.self) { try await governor.release(memory.id, owner: second) }
        #expect(await governor.usage(.admittedMemoryBytes) == 1_024)

        try await governor.release(memory.id, owner: first)
        try await governor.release(memory.id, owner: first)

        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func invalidByteCountsCannotReduceOrOverflowCharges() async throws {
        let governor = ResourceGovernor()

        for bytes in [-1, Int.max] {
            await #expect(throws: AddonFailure.self) { try await governor.admit(.state(bytes: bytes), owner: first) }
        }

        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func stateBudgetAlsoAccountsForReservationMetadata() async throws {
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 2_048))

        _ = try await governor.admit(.state(bytes: 1_024), owner: first)
        await #expect(throws: AddonFailure.self) { try await governor.admit(.temporaryMemory(bytes: 0), owner: second) }

        #expect(await governor.usage(.retainedStateBytes) == 2_048)
    }

    @Test
    func diskStateAndCacheHaveSeparateOwnerLimitsAndOneGlobalLimit() async throws {
        let governor = ResourceGovernor()
        for owner in [first, second, third] {
            _ = try await governor.admit(.diskState(bytes: 10 * 1_024 * 1_024), owner: owner)
            _ = try await governor.admit(.diskCache(bytes: 20 * 1_024 * 1_024), owner: owner)
        }

        let fourth = AddonID(rawValue: "com.example.fourth")!
        _ = try await governor.admit(.diskState(bytes: 10 * 1_024 * 1_024), owner: fourth)

        await #expect(throws: AddonFailure.self) { try await governor.admit(.diskCache(bytes: 1), owner: fourth) }
        await #expect(throws: AddonFailure.self) { try await governor.admit(.diskState(bytes: 1), owner: first) }

        #expect(await governor.usage(.diskBytes) == 100 * 1_024 * 1_024)
    }

    @Test
    func scopedReservationIsReleasedAfterFailureAndCancellation() async throws {
        let governor = ResourceGovernor()

        await #expect(throws: CancellationError.self) {
            try await governor.withReservation(.temporaryMemory(bytes: 1_024), owner: first) { _ -> Bool in
                throw CancellationError()
            }
        }

        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)

        let admitted = try await governor.withReservation(.temporaryMemory(bytes: 1_024), owner: first) { _ in
            await governor.usage(.admittedMemoryBytes)
        }

        #expect(admitted == 1_024)
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
    }
}
