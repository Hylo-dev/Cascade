//
//  ProviderAdmissionGate.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

/// ProviderAdmissionGate forwards the real provider reservation, then delays
/// only its return. This exposes the runtime's exact post-await CPU check.
actor ProviderAdmissionGate: RuntimeResourceAccess {
    nonisolated let resourceGovernorTarget: ResourceGovernor
    private var shouldGateProvider = false
    private var hasArrived = false
    private var isReleased = false
    private var arrivalContinuation: CheckedContinuation<Bool, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(target: ResourceGovernor) {
        resourceGovernorTarget = target
    }

    func armProviderAdmission() {
        shouldGateProvider = true
        hasArrived = false
        isReleased = false
    }

    func waitForArrival() async -> Bool {
        if hasArrived || isReleased { return hasArrived }
        return await withCheckedContinuation { arrivalContinuation = $0 }
    }

    func releaseGate() {
        isReleased = true
        arrivalContinuation?.resume(returning: hasArrived)
        arrivalContinuation = nil
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) async throws -> ResourceReservation {
        let reservation = try await resourceGovernorTarget.admit(request, owner: owner)
        guard case .provider = request, shouldGateProvider else { return reservation }
        shouldGateProvider = false
        hasArrived = true
        arrivalContinuation?.resume(returning: true)
        arrivalContinuation = nil
        if !isReleased {
            await withCheckedContinuation { releaseContinuation = $0 }
        }
        return reservation
    }

    func release(
        _ reservationID: UUID,
        owner           : AddonID
    ) async throws {
        try await resourceGovernorTarget.release(reservationID, owner: owner)
    }

    func reduceStateReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        toBytes bytes   : Int
    ) async -> Bool {
        await resourceGovernorTarget.reduceStateReservation(reservationID, owner: owner, toBytes: bytes)
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
