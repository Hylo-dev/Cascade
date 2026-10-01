//
//  RetainedAssetReservationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite
struct RetainedAssetReservationTests {

    let owner = AddonID(rawValue: "com.example.raster")!

    @Test
    func ordinaryAssetsAtomicallyConsumeAggregateMemory() async throws {
        let governor = ResourceGovernor()
        let asset    = try await governor.admit(.asset(bytes: 16), owner: owner)

        #expect(await governor.usage(.assetBytes) == 16)
        #expect(await governor.usage(.admittedMemoryBytes) == 16)
        #expect(await governor.usage(.retainedStateBytes) == 1_024)

        _ = try await governor.admit(.temporaryMemory(bytes: 128 * 1_024 * 1_024 - 16), owner: owner)
        await #expect(throws: AddonFailure.self) {
            try await governor.admit(.asset(bytes: 1), owner: owner)
        }

        #expect(await governor.usage(.assetBytes) == 16)

        try await governor.release(asset.id, owner: owner)
        #expect(await governor.usage(.admittedMemoryBytes) == 128 * 1_024 * 1_024 - 16)
    }

    @Test
    func protectedBackingKeepsItsChargeThroughGeneralCleanup() async throws {
        let governor = ResourceGovernor()
        let token    = try await governor.admitRetainedAsset(bytes: 16, owner: owner)

        #expect(await governor.usage(.assetBytes) == 16)
        #expect(await governor.usage(.admittedMemoryBytes) == 4_112)
        #expect(await governor.usage(.retainedStateBytes) == 5_120)

        let ordinary = try await governor.admit(.job, owner: owner)
        await #expect(throws: AddonFailure.self) {
            try await governor.release(token.reservation.id, owner: owner)
        }

        await governor.releaseAll(owner: owner)
        #expect(await governor.usage(.jobs) == 0)
        #expect(await governor.usage(.assetBytes) == 16)
        #expect(await governor.usage(.retainedStateBytes) == 5_120)

        try await governor.release(ordinary.id, owner: owner)
        try await governor.completeRetainedAsset(token, owner: owner)

        #expect(await governor.usage(.assetBytes) == 0)
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func exactLifetimeRejectsForeignOwnerAndGovernorAndDuplicateIsHarmless() async throws {
        let governor      = ResourceGovernor()
        let otherGovernor = ResourceGovernor()
        let other         = AddonID(rawValue: "com.example.other")!
        let token         = try await governor.admitRetainedAsset(bytes: 16, owner: owner)

        await #expect(throws: AddonFailure.self) {
            try await governor.completeRetainedAsset(token, owner: other)
        }
        await #expect(throws: AddonFailure.self) {
            try await otherGovernor.completeRetainedAsset(token, owner: owner)
        }
        await #expect(throws: AddonFailure.self) {
            try await governor.release(token.reservation.id, owner: other)
        }

        #expect(await governor.usage(.assetBytes) == 16)

        try await governor.completeRetainedAsset(token, owner: owner)

        let fresh = try await governor.admitRetainedAsset(bytes: 32, owner: owner)
        try await governor.completeRetainedAsset(token, owner: owner)

        #expect(await governor.usage(.assetBytes) == 32)

        try await governor.completeRetainedAsset(fresh, owner: owner)
    }

    @Test
    func fixedMetadataAndBothMemoryDimensionsAreAdmittedAtomically() async throws {
        let governor = ResourceGovernor(policy: ResourcePolicy(maximumRetainedStateBytes: 5_120))
        let token    = try await governor.admitRetainedAsset(bytes: 4, owner: owner)
        await #expect(throws: AddonFailure.self) {
            try await governor.admitRetainedAsset(bytes: 4, owner: owner)
        }

        #expect(await governor.usage(.retainedStateBytes) == 5_120)
        #expect(await governor.usage(.admittedMemoryBytes) == 4_100)

        try await governor.completeRetainedAsset(token, owner: owner)

        for bytes in [-1, Int.max] {
            await #expect(throws: AddonFailure.self) {
                try await governor.admitRetainedAsset(bytes: bytes, owner: owner)
            }
        }

        #expect(await governor.usage(.retainedStateBytes) == 0)
    }

    @Test
    func disposalTokenBindsGovernorLifetimeAfterItsOriginalActorDies() async throws {
        var original: ResourceGovernor? = ResourceGovernor()
        weak let weakOriginal = original
        let token = try await original!.admitRetainedAsset(bytes: 16, owner: owner)

        original = nil
        #expect(weakOriginal == nil)

        for _ in 0..<64 {
            let replacement = ResourceGovernor()
            await #expect(throws: AddonFailure.self) {
                try await replacement.completeRetainedAsset(token, owner: owner)
            }
        }
    }
}
