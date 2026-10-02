//
//  GatedRuntimeResourceAccess.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
@testable import CascadeRuntime

/// GatedRuntimeResourceAccess withholds one observed-disk reconciliation return after
/// forwarding the real governor mutation exactly once. It never fabricates reservations or
/// outcomes: every other call goes straight to the governor, and cancelling the held caller
/// opens the gate, so a test can cancel work parked right after a committed accounting step.
actor GatedRuntimeResourceAccess: RuntimeResourceAccess {

    nonisolated let resourceGovernorTarget: ResourceGovernor

    private var shouldGateWorkspaceReconcile = false

    private var hasArrived          = false
    private var isReleased          = false
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(target: ResourceGovernor) {
        resourceGovernorTarget = target
    }

    /// armWorkspaceReconcile holds the next reconciliation return after its real mutation.
    func armWorkspaceReconcile() {
        shouldGateWorkspaceReconcile = true
        hasArrived                   = false
        isReleased                   = false
    }

    func waitForArrival() async {
        if hasArrived || isReleased { return }
        await withCheckedContinuation { continuation in
            arrivalContinuation = continuation
        }
    }

    func releaseGate() {
        isReleased = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    private func waitForRelease() async {
        if isReleased { return }
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                releaseContinuation = continuation
            }
        } onCancel: {
            Task { await self.releaseGate() }
        }
    }

    func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) async throws -> ResourceReservation {
        try await resourceGovernorTarget.admit(request, owner: owner)
    }

    func release(
        _ reservationID: UUID,
        owner          : AddonID
    ) async throws {
        try await resourceGovernorTarget.release(reservationID, owner: owner)
    }

    func resizeStateReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        fromBytes      : Int,
        toBytes        : Int
    ) async throws -> Bool {
        try await resourceGovernorTarget.resizeStateReservation(
            reservationID,
            owner    : owner,
            fromBytes: fromBytes,
            toBytes  : toBytes
        )
    }

    func workspaceReconcileObservedDisk(
        _ token      : ObservedDiskToken,
        owner        : AddonID,
        fromBytes    : Int,
        measuredBytes: Int
    ) async throws -> Bool {
        let shouldGate               = shouldGateWorkspaceReconcile
        shouldGateWorkspaceReconcile = false
        let result                   = try await resourceGovernorTarget.reconcileObservedDisk(
            token,
            owner        : owner,
            fromBytes    : fromBytes,
            measuredBytes: measuredBytes
        )
        guard shouldGate else { return result }

        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        if isReleased { return result }
        await waitForRelease()
        return result
    }
}
