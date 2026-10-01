//
//  StateReservationResizeTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct StateReservationResizeTests {

    let first : AddonID
    let second: AddonID
    let third : AddonID

    init() throws {
        first  = try #require(AddonID(rawValue: "com.example.resize.first"))
        second = try #require(AddonID(rawValue: "com.example.resize.second"))
        third  = try #require(AddonID(rawValue: "com.example.resize.third"))
    }

    @Test
    func growthUsesOnlyThePayloadDeltaAndKeepsReservationMetadata() async throws {
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 8_192))
        let state    = try await governor.admit(.state(bytes: 2_048), owner: first)
        _ = try await governor.admit(.job, owner: second)
        _ = try await governor.admit(.state(bytes: 2_048), owner: third)

        #expect(await governor.usage(.retainedStateBytes) == 7_168)
        #expect(try await governor.resizeStateReservation(
            state.id,
            owner    : first,
            fromBytes: 2_048,
            toBytes  : 3_072
        ))
        #expect(await governor.usage(.retainedStateBytes) == 8_192)
        #expect(await governor.usage(.retainedStateBytes, owner: first) == 4_096)
    }

    @Test
    func quotaFailureLeavesEveryCounterAndTheOriginalSizeUnchanged() async throws {
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 8_192))
        let state    = try await governor.admit(.state(bytes: 2_048), owner: first)
        _ = try await governor.admit(.state(bytes: 3_072), owner: second)

        do {
            _ = try await governor.resizeStateReservation(
                state.id,
                owner    : first,
                fromBytes: 2_048,
                toBytes  : 3_073
            )
            Issue.record("Expected growth beyond the remaining global quota to be denied.")
        } catch let failure as AddonFailure {
            #expect(failure.code == .resourceDenied)
        }

        #expect(await governor.usage(.retainedStateBytes) == 7_168)
        #expect(await governor.usage(.retainedStateBytes, owner: first) == 3_072)
        #expect(await governor.usage(.retainedStateBytes, owner: second) == 4_096)
        #expect(try await governor.resizeStateReservation(
            state.id,
            owner    : first,
            fromBytes: 2_048,
            toBytes  : 3_072
        ))
    }

    @Test
    func sameSizeAndShrinkSucceedAtFullCapacity() async throws {
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 8_192))
        let state    = try await governor.admit(.state(bytes: 6_144), owner: first)
        _ = try await governor.admit(.job, owner: second)

        #expect(await governor.usage(.retainedStateBytes) == 8_192)
        #expect(try await governor.resizeStateReservation(
            state.id,
            owner    : first,
            fromBytes: 6_144,
            toBytes  : 6_144
        ))
        #expect(await governor.usage(.retainedStateBytes) == 8_192)
        #expect(try await governor.resizeStateReservation(
            state.id,
            owner    : first,
            fromBytes: 6_144,
            toBytes  : 3_072
        ))
        #expect(await governor.usage(.retainedStateBytes) == 5_120)
        #expect(await governor.usage(.retainedStateBytes, owner: first) == 4_096)
    }

    @Test
    func ownershipPrecedesKindSizesAndDesiredAmountValidation() async throws {
        let governor = ResourceGovernor()
        let state    = try await governor.admit(.state(bytes: 128), owner: first)
        let provider = try await governor.admit(.provider, owner: first)

        do {
            _ = try await governor.resizeStateReservation(
                provider.id,
                owner    : second,
                fromBytes: -1,
                toBytes  : Int.max
            )
            Issue.record("Expected a canonical reservation owner mismatch to be denied.")
        } catch let failure as AddonFailure {
            #expect(failure.code == .permissionDenied)
        }

        #expect(try await !governor.resizeStateReservation(
            UUID(),
            owner    : second,
            fromBytes: -1,
            toBytes  : Int.max
        ))
        #expect(try await !governor.resizeStateReservation(
            provider.id,
            owner    : first,
            fromBytes: 0,
            toBytes  : Int.max
        ))
        #expect(try await !governor.resizeStateReservation(
            state.id,
            owner    : first,
            fromBytes: -1,
            toBytes  : Int.max
        ))
        #expect(await governor.usage(.retainedStateBytes) == 2_176)
        #expect(await governor.usage(.providers) == 1)
        #expect(await governor.usage(.admittedMemoryBytes) == 64 * 1_024 * 1_024)
    }

    @Test
    func malformedDesiredAmountsAreResourceDeniedWithoutMutation() async throws {
        let governor = ResourceGovernor()
        let state    = try await governor.admit(.state(bytes: 128), owner: first)

        for desiredBytes in [-1, Int.max] {
            do {
                _ = try await governor.resizeStateReservation(
                    state.id,
                    owner    : first,
                    fromBytes: 128,
                    toBytes  : desiredBytes
                )
                Issue.record("Expected a malformed desired payload size to be denied.")
            } catch let failure as AddonFailure {
                #expect(failure.code == .resourceDenied)
            }

            #expect(await governor.usage(.retainedStateBytes) == 1_152)
            #expect(await governor.usage(.retainedStateBytes, owner: first) == 1_152)
        }

        #expect(try await governor.resizeStateReservation(
            state.id,
            owner    : first,
            fromBytes: 128,
            toBytes  : 256
        ))
    }

    @Test
    func releasedReservationReturnsFalseBeforeDesiredAmountValidation() async throws {
        let governor = ResourceGovernor()
        let state    = try await governor.admit(.state(bytes: 128), owner: first)
        try await governor.release(state.id, owner: first)

        #expect(try await !governor.resizeStateReservation(
            state.id,
            owner    : second,
            fromBytes: 128,
            toBytes  : Int.max
        ))
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func concurrentTransitionsFromOneExpectedSizeHaveExactlyOneWinner() async throws {
        let governor = ResourceGovernor()
        let state    = try await governor.admit(.state(bytes: 100), owner: first)
        var outcomes: [Bool] = []

        try await withThrowingTaskGroup(of: Bool.self) { group in
            for desiredBytes in [200, 300] {
                group.addTask {
                    try await governor.resizeStateReservation(
                        state.id,
                        owner    : self.first,
                        fromBytes: 100,
                        toBytes  : desiredBytes
                    )
                }
            }
            for try await outcome in group {
                outcomes.append(outcome)
            }
        }

        #expect(outcomes.filter { $0 }.count == 1)

        let finalUsage = await governor.usage(.retainedStateBytes)
        #expect(finalUsage == 1_224 || finalUsage == 1_324)
        #expect(await governor.usage(.retainedStateBytes, owner: first) == finalUsage)
    }

    @Test
    func releaseAfterGrowthReturnsTheFinalChargeAndPreservesOtherOwners() async throws {
        let governor = ResourceGovernor()
        let state    = try await governor.admit(.state(bytes: 128), owner: first)
        let provider = try await governor.admit(.provider, owner: second)

        #expect(try await governor.resizeStateReservation(
            state.id,
            owner    : first,
            fromBytes: 128,
            toBytes  : 2_048
        ))

        try await governor.release(state.id, owner: first)
        #expect(await governor.usage(.retainedStateBytes) == 1_024)
        #expect(await governor.usage(.providers) == 1)
        #expect(await governor.usage(.admittedMemoryBytes) == 64 * 1_024 * 1_024)
        #expect(await governor.usage(.retainedStateBytes, owner: second) == 1_024)

        try await governor.release(provider.id, owner: second)
        #expect(await governor.usage(.retainedStateBytes) == 0)
        #expect(await governor.usage(.providers) == 0)
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
    }
}
