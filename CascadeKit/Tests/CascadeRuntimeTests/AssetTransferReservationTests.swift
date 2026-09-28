//
//  AssetTransferReservationTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

@Suite struct AssetTransferReservationTests {
    @Test func protectedQuoteAndCompletion() async throws {
        let owner = try #require(AddonID(rawValue: "com.example.transfer"))
        let governor = ResourceGovernor()
        let token = try await governor.admitAssetTransfer(
            bytes: 65_536,
            owner: owner
        )
        #expect(await governor.usage(.admittedMemoryBytes) == 135_168)
        #expect(await governor.usage(.retainedStateBytes) == 1_024)
        #expect(await governor.usage(.assetBytes) == 0)
        await governor.releaseAll(owner: owner)
        #expect(await governor.usage(.admittedMemoryBytes) == 135_168)
        try await governor.completeAssetTransfer(
            token,
            owner: owner
        )
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
        #expect(await governor.usage(.retainedStateBytes) == 0)
    }
}

extension AssetTransferReservationTests {
    @Test func tokenAuthorityAndInvalidAdmissionRemainAtomic() async throws {
        let owner = try #require(AddonID(rawValue: "com.example.transfer"))
        let foreign = try #require(AddonID(rawValue: "com.example.foreign"))
        let governor = ResourceGovernor()
        let other = ResourceGovernor()
        for bytes in [Int.min, -1, 0, 1_048_577, Int.max] {
            await #expect(throws: AddonFailure.self) { try await governor.admitAssetTransfer(
                bytes: bytes,
                owner: owner
            ) }
        }
        #expect(await governor.usage(.retainedStateBytes) == 0)
        let token = try await governor.admitAssetTransfer(
            bytes: 1_048_576,
            owner: owner
        )
        await #expect(throws: AddonFailure.self) { try await governor.release(
            token.reservation.id,
            owner: owner
        ) }
        await #expect(throws: AddonFailure.self) { try await governor.completeAssetTransfer(
            token,
            owner: foreign
        ) }
        await #expect(throws: AddonFailure.self) { try await other.completeAssetTransfer(
            token,
            owner: owner
        ) }
        #expect(await governor.reduceStateReservation(
            token.reservation.id,
            owner  : owner,
            toBytes: 0
        ) == false)
        #expect(try await governor.resizeDiskReservation(
            token.reservation.id,
            owner    : owner,
            fromBytes: 0,
            toBytes  : 1
        ) == false)
        #expect(await governor.usage(.admittedMemoryBytes) == 2_101_248)
        try await governor.completeAssetTransfer(
            token,
            owner: owner
        )
        let fresh = try await governor.admitAssetTransfer(
            bytes: 1,
            owner: owner
        )
        try await governor.completeAssetTransfer(
            token,
            owner: owner
        )
        #expect(await governor.usage(.admittedMemoryBytes) == 4_098)
        try await governor.completeAssetTransfer(
            fresh,
            owner: owner
        )
        let held = try await governor.admit(
            .temporaryMemory(bytes: 128 * 1_024 * 1_024),
            owner: owner
        )
        await #expect(throws: AddonFailure.self) { try await governor.admitAssetTransfer(
            bytes: 1,
            owner: owner
        ) }
        #expect(await governor.usage(.retainedStateBytes) == 1_024)
        try await governor.release(
            held.id,
            owner: owner
        )
        #expect(await governor.usage(.admittedMemoryBytes) == 0)
    }
}
