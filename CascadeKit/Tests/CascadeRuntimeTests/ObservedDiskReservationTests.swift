//
//  ObservedDiskReservationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct ObservedDiskReservationTests {

    private let first : AddonID
    private let second: AddonID
    private let mib    = 1_024 * 1_024

    init() throws {
        first  = try #require(AddonID(rawValue: "com.example.observed.first"))
        second = try #require(AddonID(rawValue: "com.example.observed.second"))
    }

    @Test
    func observedDebtSurvivesGenericCleanupAndBlocksOwnerDiskGrowth() async throws {
        let governor = ResourceGovernor()
        let token    = try await governor.admitObservedDisk(bytes: 1, owner: first)
        _            = try await governor.admit(.diskCache(bytes: 1), owner: first)

        #expect(try await governor.reconcileObservedDisk(
            token,
            owner        : first,
            fromBytes    : 1,
            measuredBytes: 11 * mib
        ))

        let status = try await governor.observedDiskStatus(token, owner: first)

        #expect(status.bytes == 11 * mib)
        #expect(status.ownerOverageBytes == mib)
        #expect(status.globalOverageBytes == 0)
        #expect(!status.permitsWrites)
        #expect(await governor.usage(.diskBytes) == 11 * mib + 1)

        await #expect(throws: AddonFailure.self) {
            try await governor.admit(.diskCache(bytes: 1), owner: first)
        }

        await #expect(throws: AddonFailure.self) {
            try await governor.release(token.reservation.id, owner: first)
        }

        await governor.releaseAll(owner: first)
        #expect(await governor.usage(.diskBytes) == 11 * mib)
        #expect(await governor.usage(.retainedStateBytes) == ResourcePolicy.reservationCharge)

        _ = try await governor.admit(.diskState(bytes: 1), owner: second)
    }

    @Test
    func strictGrowthCannotCreateDebtAndOnlyMeasuredZeroAllowsFinalRelease() async throws {
        let governor = ResourceGovernor()
        let token    = try await governor.admitObservedDisk(bytes: 0, owner: first)

        #expect(try await governor.growObservedDisk(
            token,
            owner    : first,
            fromBytes: 0,
            toBytes  : 10 * mib
        ))

        await #expect(throws: AddonFailure.self) {
            try await governor.growObservedDisk(
                token,
                owner    : first,
                fromBytes: 10 * mib,
                toBytes  : 10 * mib + 1
            )
        }

        await #expect(throws: AddonFailure.self) {
            try await governor.growObservedDisk(
                token,
                owner    : first,
                fromBytes: 10 * mib,
                toBytes  : 0
            )
        }

        await #expect(throws: AddonFailure.self) {
            try await governor.completeObservedDisk(token, owner: first)
        }

        #expect(await governor.usage(.diskBytes) == 10 * mib)
        #expect(try await governor.reconcileObservedDisk(
            token,
            owner        : first,
            fromBytes    : 10 * mib,
            measuredBytes: 0
        ))

        try await governor.completeObservedDisk(token, owner: first)

        #expect(await governor.usage(.retainedStateBytes) == 0)

        await #expect(throws: AddonFailure.self) {
            try await governor.reconcileObservedDisk(
                token,
                owner        : first,
                fromBytes    : 0,
                measuredBytes: 1
            )
        }
    }

    @Test
    func globalDebtSurvivesOtherOwnerShrinkAndRetainsAllCharges() async throws {
        let governor    = ResourceGovernor()
        let firstToken  = try await governor.admitObservedDisk(bytes: 0, owner: first)
        let secondToken = try await governor.admitObservedDisk(bytes: 0, owner: second)

        #expect(try await governor.reconcileObservedDisk(
            firstToken,
            owner        : first,
            fromBytes    : 0,
            measuredBytes: 101 * mib
        ))
        #expect(try await governor.reconcileObservedDisk(
            secondToken,
            owner        : second,
            fromBytes    : 0,
            measuredBytes: 12 * mib
        ))
        #expect(try await governor.reconcileObservedDisk(
            secondToken,
            owner        : second,
            fromBytes    : 12 * mib,
            measuredBytes: 0
        ))

        let status = try await governor.observedDiskStatus(secondToken, owner: second)

        #expect(status.ownerOverageBytes == 0)
        #expect(status.globalOverageBytes == mib)
        #expect(!status.permitsWrites)

        await #expect(throws: AddonFailure.self) {
            try await governor.admit(.diskCache(bytes: 1), owner: second)
        }

        #expect(await governor.usage(.diskStateBytes) == 101 * mib)
        #expect(try await governor.reconcileObservedDisk(
            firstToken,
            owner        : first,
            fromBytes    : 101 * mib,
            measuredBytes: 10 * mib
        ))
        #expect(try await governor.observedDiskStatus(secondToken, owner: second).permitsWrites)

        _ = try await governor.admit(.diskCache(bytes: 1), owner: second)
    }

    @Test
    func foreignOwnerGovernorAndStaleSizeCannotChangeCanonicalBytes() async throws {
        let governor = ResourceGovernor()
        let foreign  = ResourceGovernor()
        let token    = try await governor.admitObservedDisk(bytes: 7, owner: first)

        await #expect(throws: AddonFailure.self) {
            try await foreign.reconcileObservedDisk(
                token,
                owner        : first,
                fromBytes    : 7,
                measuredBytes: 0
            )
        }

        await #expect(throws: AddonFailure.self) {
            try await governor.reconcileObservedDisk(
                token,
                owner        : second,
                fromBytes    : 7,
                measuredBytes: 0
            )
        }

        #expect(try await !governor.reconcileObservedDisk(
            token,
            owner        : first,
            fromBytes    : 6,
            measuredBytes: 0
        ))
        #expect(try await !governor.growObservedDisk(
            token,
            owner    : first,
            fromBytes: 6,
            toBytes  : 8
        ))
        #expect(await governor.usage(.diskBytes) == 7)
        #expect(await foreign.usage(.diskBytes) == 0)
    }

    @Test
    func malformedAndOverflowObservationsAreAtomicAndPreserveOtherReservations() async throws {
        let governor = ResourceGovernor()
        let token    = try await governor.admitObservedDisk(bytes: 3, owner: first)

        _ = try await governor.admit(.diskCache(bytes: 1), owner: second)

        for measuredBytes in [-1, Int.max] {
            await #expect(throws: AddonFailure.self) {
                try await governor.reconcileObservedDisk(
                    token,
                    owner        : first,
                    fromBytes    : 3,
                    measuredBytes: measuredBytes
                )
            }
        }

        #expect(await governor.usage(.diskStateBytes) == 3)
        #expect(await governor.usage(.diskBytes) == 4)
        #expect(await governor.usage(.diskBytes, owner: second) == 1)
        #expect(try await governor.observedDiskStatus(token, owner: first).permitsWrites)
    }

    @Test
    func initialAdmissionIsStrictAndMetadataRemainsBounded() async throws {
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 1_024))
        for bytes in [-1, 10 * mib + 1, Int.max] {
            await #expect(throws: AddonFailure.self) {
                try await governor.admitObservedDisk(bytes: bytes, owner: first)
            }
        }

        #expect(await governor.usage(.retainedStateBytes) == 0)

        _ = try await governor.admitObservedDisk(bytes: 0, owner: first)

        await #expect(throws: AddonFailure.self) {
            try await governor.admitObservedDisk(bytes: 0, owner: second)
        }

        #expect(await governor.usage(.retainedStateBytes) == 1_024)
    }

    @Test
    func zeroTokenCanObserveNewInventoryWhileExistingDiskIsOverbudget() async throws {
        let governor = ResourceGovernor()
        let existing = try await governor.admitObservedDisk(bytes: 0, owner: first)

        #expect(try await governor.reconcileObservedDisk(
            existing,
            owner        : first,
            fromBytes    : 0,
            measuredBytes: 101 * mib
        ))

        let discovered = try await governor.admitObservedDisk(bytes: 0, owner: first)

        #expect(try await governor.reconcileObservedDisk(
            discovered,
            owner        : first,
            fromBytes    : 0,
            measuredBytes: 1
        ))
        #expect(await governor.usage(.diskBytes) == 101 * mib + 1)
        #expect(await governor.usage(.retainedStateBytes) == 2 * ResourcePolicy.reservationCharge)

        await #expect(throws: AddonFailure.self) {
            try await governor.admitObservedDisk(bytes: 1, owner: second)
        }
    }

    @Test
    func retainedMetadataIsPrepaidProtectedAndReclaimedOnlyWithItsLedger() async throws {
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 18 * 1_024))
        let existing = try await governor.admitObservedDisk(bytes: 0, owner: first)

        #expect(try await governor.reconcileObservedDisk(
            existing,
            owner        : first,
            fromBytes    : 0,
            measuredBytes: 101 * mib
        ))

        let token = try await governor.admitObservedDisk(
            bytes                : 0,
            owner                : first,
            retainedMetadataBytes: 16 * 1_024
        )

        #expect(await governor.usage(.retainedStateBytes) == 18 * 1_024)
        #expect(await governor.usage(.admittedMemoryBytes) == 16 * 1_024)

        for metadataBytes in [-1, Int.max, 8 * mib, 0] {
            await #expect(throws: AddonFailure.self) {
                try await governor.admitObservedDisk(
                    bytes                : 0,
                    owner                : second,
                    retainedMetadataBytes: metadataBytes
                )
            }
        }

        #expect(try await !governor.resizeStateReservation(
            token.reservation.id,
            owner    : first,
            fromBytes: 16 * 1_024,
            toBytes  : 0
        ))

        await governor.releaseAll(owner: first)
        #expect(await governor.usage(.retainedStateBytes) == 18 * 1_024)
        #expect(await governor.usage(.admittedMemoryBytes) == 16 * 1_024)
        #expect(await governor.usage(.diskBytes) == 101 * mib)
        #expect(try await governor.reconcileObservedDisk(
            token,
            owner        : first,
            fromBytes    : 0,
            measuredBytes: 0
        ))

        try await governor.completeObservedDisk(token, owner: first)

        #expect(await governor.usage(.retainedStateBytes) == 1_024)
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        #expect(await governor.usage(.diskBytes) == 101 * mib)
    }
}
