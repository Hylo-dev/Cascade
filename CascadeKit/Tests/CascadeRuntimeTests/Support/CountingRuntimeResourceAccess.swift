//
//  CountingRuntimeResourceAccess.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

actor CountingRuntimeResourceAccess: RuntimeResourceAccess {
    nonisolated let resourceGovernorTarget: ResourceGovernor
    private(set) var admissionCount = 0

    init(target: ResourceGovernor) {
        resourceGovernorTarget = target
    }

    func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) async throws -> ResourceReservation {
        admissionCount += 1
        return try await resourceGovernorTarget.admit(
            request,
            owner: owner
        )
    }

    func release(
        _ reservationID: UUID,
        owner           : AddonID
    ) async throws {
        try await resourceGovernorTarget.release(
            reservationID,
            owner: owner
        )
    }

    func reduceStateReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        toBytes bytes   : Int
    ) async -> Bool {
        await resourceGovernorTarget.reduceStateReservation(
            reservationID,
            owner  : owner,
            toBytes: bytes
        )
    }

    func resizeStateReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        fromBytes       : Int,
        toBytes         : Int
    ) async throws -> Bool {
        try await resourceGovernorTarget.resizeStateReservation(
            reservationID,
            owner    : owner,
            fromBytes: fromBytes,
            toBytes  : toBytes
        )
    }
    func resizeDiskReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        fromBytes       : Int,
        toBytes         : Int
    ) async throws -> Bool {
        try await resourceGovernorTarget.resizeDiskReservation(
            reservationID,
            owner    : owner,
            fromBytes: fromBytes,
            toBytes  : toBytes
        )
    }

}
