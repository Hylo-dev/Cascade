//
//  DiskReservationResizeTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct DiskReservationResizeTests {
    @Test
    func growsBothDimensionsPreservingMetadataAndReservationIdentity() async throws {
        let owner = try #require(AddonID(rawValue: "com.example.disk"))
        let governor = ResourceGovernor()
        let reservation = try await governor.admit(.diskState(bytes: 100), owner: owner)
        #expect(
            try await governor.resizeDiskReservation(
                reservation.id,
                owner: owner,
                fromBytes: 100,
                toBytes: 200
            )
        )
        #expect(await governor.usage(.diskStateBytes, owner: owner) == 200)
        #expect(await governor.usage(.diskBytes) == 200)
        #expect(await governor.usage(.retainedStateBytes) == 1_024)
        try await governor.release(reservation.id, owner: owner)
        #expect(await governor.usage(.diskBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func rejectsWrongOwnerKindExpectedAndMalformedAmountsWithoutMutation() async throws {
        let owner = try #require(AddonID(rawValue: "com.example.disk"))
        let other = try #require(AddonID(rawValue: "com.example.other"))
        let governor = ResourceGovernor()
        let disk = try await governor.admit(.diskCache(bytes: 100), owner: owner)
        let state = try await governor.admit(.state(bytes: 100), owner: owner)
        #expect(try await governor.resizeDiskReservation(UUID(), owner: other, fromBytes: -1, toBytes: -1) == false)
        do {
            _ = try await governor.resizeDiskReservation(disk.id, owner: other, fromBytes: -1, toBytes: -1)
            Issue.record("Wrong owner was accepted")
        } catch let failure as AddonFailure { #expect(failure.code == .permissionDenied) }
        #expect(try await governor.resizeDiskReservation(state.id, owner: owner, fromBytes: 100, toBytes: -1) == false)
        #expect(try await governor.resizeDiskReservation(disk.id, owner: owner, fromBytes: 99, toBytes: -1) == false)
        for desired in [-1, Int.max, 20 * 1_024 * 1_024 + 1] {
            do {
                _ = try await governor.resizeDiskReservation(disk.id, owner: owner, fromBytes: 100, toBytes: desired)
                Issue.record("Malformed growth was accepted")
            } catch let failure as AddonFailure { #expect(failure.code == .resourceDenied) }
        }
        #expect(await governor.usage(.diskCacheBytes) == 100)
        #expect(await governor.usage(.diskBytes) == 100)
        #expect(await governor.usage(.retainedStateBytes) == 2_148)
    }

    @Test
    func sameSizeAndShrinkWorkAtFullOwnerClassAndGlobalDiskQuotas() async throws {
        let governor = ResourceGovernor()
        let owner = try #require(AddonID(rawValue: "com.example.disk"))
        let state = try await governor.admit(.diskState(bytes: 10 * 1_024 * 1_024), owner: owner)
        let cache = try await governor.admit(.diskCache(bytes: 20 * 1_024 * 1_024), owner: owner)
        for index in 0..<7 {
            let other = try #require(AddonID(rawValue: "com.example.disk.other\(index)"))
            _ = try await governor.admit(.diskState(bytes: 10 * 1_024 * 1_024), owner: other)
        }
        #expect(await governor.usage(.diskBytes) == 100 * 1_024 * 1_024)
        #expect(
            try await governor.resizeDiskReservation(
                cache.id,
                owner: owner,
                fromBytes: 20 * 1_024 * 1_024,
                toBytes: 20 * 1_024 * 1_024
            )
        )
        #expect(
            try await governor.resizeDiskReservation(
                state.id,
                owner: owner,
                fromBytes: 10 * 1_024 * 1_024,
                toBytes: 1
            )
        )
        #expect(await governor.usage(.diskStateBytes, owner: owner) == 1)
        #expect(await governor.usage(.diskBytes, owner: owner) == 20 * 1_024 * 1_024 + 1)
        #expect(await governor.usage(.retainedStateBytes) == 9 * 1_024)
        try await governor.release(state.id, owner: owner)
        #expect(await governor.usage(.diskStateBytes, owner: owner) == 0)
    }

    @Test
    func globalGrowthRefusalDoesNotMutateClassOrMetadata() async throws {
        let governor = ResourceGovernor()
        let owner = try #require(AddonID(rawValue: "com.example.disk"))
        let disk = try await governor.admit(.diskCache(bytes: 1), owner: owner)
        for index in 0..<10 {
            let other = try #require(AddonID(rawValue: "com.example.full\(index)"))
            _ = try await governor.admit(.diskState(bytes: 10 * 1_024 * 1_024 - (index == 0 ? 1 : 0)), owner: other)
        }
        do {
            _ = try await governor.resizeDiskReservation(disk.id, owner: owner, fromBytes: 1, toBytes: 2)
            Issue.record("Full global disk quota allowed growth")
        } catch let failure as AddonFailure { #expect(failure.code == .resourceDenied) }
        #expect(await governor.usage(.diskCacheBytes) == 1)
        #expect(await governor.usage(.diskBytes) == 100 * 1_024 * 1_024)
        #expect(await governor.usage(.retainedStateBytes) == 11 * 1_024)
    }
}
