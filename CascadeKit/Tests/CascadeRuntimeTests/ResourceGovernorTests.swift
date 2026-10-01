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
    func jobsAreBoundedPerOwnerAndGloballyAndReleaseRestoresCapacity() async throws {
        let governor = ResourceGovernor()
        let firstJob = try await governor.admit(.job, owner: first)

        await #expect(throws: AddonFailure.self) { try await governor.admit(.job, owner: first) }

        _ = try await governor.admit(.job, owner: second)
        await #expect(throws: AddonFailure.self) { try await governor.admit(.job, owner: third) }

        try await governor.release(firstJob.id, owner: first)
        _ = try await governor.admit(.job, owner: third)

        #expect(await governor.usage(.jobs) == 2)
    }

    @Test
    func activityAndInstanceLimitsApplyAcrossReservations() async throws {
        let governor = ResourceGovernor()
        for _ in 0..<4 { _ = try await governor.admit(.publication(.activity), owner: first) }
        await #expect(throws: AddonFailure.self) { try await governor.admit(.publication(.activity), owner: first) }

        for _ in 0..<12 { _ = try await governor.admit(.publication(.widget), owner: first) }
        await #expect(throws: AddonFailure.self) { try await governor.admit(.publication(.widget), owner: first) }

        #expect(await governor.usage(.publications, owner: first) == 16)
        #expect(await governor.usage(.activities, owner: first) == 4)
    }

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
        let job      = try await governor.admit(.job, owner: first)

        await #expect(throws: AddonFailure.self) { try await governor.release(job.id, owner: second) }
        #expect(await governor.usage(.jobs) == 1)

        try await governor.release(job.id, owner: first)
        try await governor.release(job.id, owner: first)

        #expect(await governor.usage(.jobs) == 0)
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
    func commandsAreBoundedAndOwnerRevocationReleasesEveryCharge() async throws {
        let governor = ResourceGovernor()

        for _ in 0..<4 { _ = try await governor.admit(.command, owner: first) }
        await #expect(throws: AddonFailure.self) { try await governor.admit(.command, owner: first) }

        _ = try await governor.admit(.job, owner: second)
        await governor.releaseAll(owner: first)

        #expect(await governor.usage(.commands) == 0)
        #expect(await governor.usage(.jobs, owner: second) == 1)
        #expect(await governor.usage(.retainedStateBytes, owner: first) == 0)
    }

    @Test
    func processAdmissionCountsAllWorkersAndTheirMemory() async throws {
        let governor = ResourceGovernor()
        _ = try await governor.admit(.provider, owner: first)
        _ = try await governor.admit(.provider, owner: second)
        _ = try await governor.admit(.provider, owner: third)
        _ = try await governor.admit(.scene, owner: first)

        await #expect(throws: AddonFailure.self) {
            try await governor.admit(.provider, owner: AddonID(rawValue: "com.example.fourth")!)
        }
        await #expect(throws: AddonFailure.self) { try await governor.admit(.scene, owner: second) }

        #expect(await governor.usage(.admittedMemoryBytes) == 256 * 1_024 * 1_024)
    }

    @Test
    func stateBudgetAlsoAccountsForReservationMetadata() async throws {
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 2_048))

        _ = try await governor.admit(.state(bytes: 1_024), owner: first)
        await #expect(throws: AddonFailure.self) { try await governor.admit(.job, owner: second) }

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
            try await governor.withReservation(.job, owner: first) { _ -> Bool in
                throw CancellationError()
            }
        }

        #expect(await governor.usage(.jobs) == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)

        let admitted = try await governor.withReservation(.job, owner: first) { _ in
            await governor.usage(.jobs)
        }

        #expect(admitted == 1)
        #expect(await governor.usage(.jobs) == 0)
    }

    @Test
    func stateReductionAtFullCapacityReturnsBytesWithoutReadmission() async throws {
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 8_192))
        let state    = try await governor.admit(.state(bytes: 6_144), owner: first)
        let job      = try await governor.admit(.job, owner: second)

        #expect(await governor.usage(.retainedStateBytes) == 8_192)

        #expect(await governor.reduceStateReservation(state.id, owner: first, toBytes: 3_072))
        #expect(await governor.usage(.retainedStateBytes) == 5_120)
        #expect(await governor.usage(.retainedStateBytes, owner: first) == 4_096)
        #expect(await governor.usage(.retainedStateBytes, owner: second) == 1_024)

        let replacement = try await governor.admit(.state(bytes: 2_048), owner: third)
        #expect(await governor.usage(.retainedStateBytes) == 8_192)

        try await governor.release(state.id, owner: first)
        #expect(await governor.usage(.retainedStateBytes) == 4_096)

        #expect(await governor.usage(.retainedStateBytes, owner: first) == 0)
        #expect(await governor.usage(.jobs) == 1)

        try await governor.release(job.id, owner: second)
        try await governor.release(replacement.id, owner: third)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func invalidReductionsDoNotChangeKindsOwnersOrMetadata() async throws {
        let governor = ResourceGovernor()
        let state    = try await governor.admit(.state(bytes: 128), owner: first)
        let job      = try await governor.admit(.job, owner: first)
        let provider = try await governor.admit(.provider, owner: second)
        let asset    = try await governor.admit(.asset(bytes: 0), owner: third)

        for (id, owner, count) in [
            (state.id, second, 0), (UUID(), first, 0), (job.id, first, 0),
            (provider.id, second, 0), (asset.id, third, 0),
            (state.id, first, -1), (state.id, first, 129), (state.id, first, Int.max)
        ] {
            #expect(await !governor.reduceStateReservation(id, owner: owner, toBytes: count))
            #expect(await governor.usage(.retainedStateBytes) == 4_224)
            #expect(await governor.usage(.retainedStateBytes, owner: first) == 2_176)
        }

        #expect(await governor.reduceStateReservation(state.id, owner: first, toBytes: 0))
        #expect(await governor.reduceStateReservation(state.id, owner: first, toBytes: 0))
        #expect(await !governor.reduceStateReservation(state.id, owner: first, toBytes: 1))

        #expect(await governor.usage(.retainedStateBytes) == 4_096)
        #expect(await governor.usage(.jobs) == 1)
        #expect(await governor.usage(.providers) == 1)
        #expect(await governor.usage(.admittedMemoryBytes) == 67_108_864)

        try await governor.release(state.id, owner: first)
        try await governor.release(state.id, owner: first)

        #expect(await !governor.reduceStateReservation(state.id, owner: first, toBytes: 0))
        #expect(await governor.usage(.retainedStateBytes) == 3_072)

        for reservation in [job, provider, asset] {
            try await governor.release(reservation.id, owner: reservation.owner)
        }

        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func scopedAndConcurrentCleanupSubtractOnlyTheRemainingStateCharge() async throws {
        let governor  = ResourceGovernor()
        let unrelated = try await governor.admit(.job, owner: second)

        await #expect(throws: CancellationError.self) {
            try await governor.withReservation(.state(bytes: 128), owner: first) { reservation -> Bool in
                #expect(await governor.reduceStateReservation(reservation.id, owner: first, toBytes: 0))
                throw CancellationError()
            }
        }

        #expect(await governor.usage(.retainedStateBytes) == 1_024)

        let state = try await governor.admit(.state(bytes: 128), owner: first)

        try await withThrowingTaskGroup(of: Void.self) { group in
            for count in [0, 32, 64, 128, 0, 64] {
                group.addTask { _ = await governor.reduceStateReservation(state.id, owner: first, toBytes: count) }
            }

            group.addTask { try await governor.release(state.id, owner: first) }
            group.addTask { try await governor.release(state.id, owner: first) }
            try await group.waitForAll()
        }

        #expect(await governor.usage(.retainedStateBytes) == 1_024)
        #expect(await governor.usage(.retainedStateBytes, owner: first) == 0)
        #expect(await governor.usage(.jobs) == 1)

        try await governor.release(unrelated.id, owner: second)

        #expect(await governor.usage(.retainedStateBytes) == 0)
    }
}
