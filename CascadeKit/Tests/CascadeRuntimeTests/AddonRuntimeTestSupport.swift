//
//  AddonRuntimeTestSupport.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
@testable import CascadeRuntime

/// GatedRuntimeResourceAccess withholds one post-resize return after forwarding the
/// real governor mutation exactly once. It never fabricates reservations or outcomes.
actor GatedRuntimeResourceAccess: RuntimeResourceAccess {

    nonisolated let resourceGovernorTarget: ResourceGovernor

    private var shouldGateRelease            = false
    private var shouldGateResize             = false
    private var shouldGateReduction          = false
    private var shouldGateTemporaryMemory    = false
    private var shouldGateStateAdmission     = false
    private var shouldGateJobAdmission       = false
    private var shouldGateWorkspaceReconcile = false

    private var hasArrived          = false
    private var isReleased          = false
    private var arrivalContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    init(target: ResourceGovernor) {
        resourceGovernorTarget = target
    }

    /// armRelease holds one real refund return after its canonical governor mutation.
    func armRelease() {
        shouldGateRelease = true
        hasArrived        = false
        isReleased        = false
    }

    func armResize() {
        shouldGateResize = true
        hasArrived       = false
        isReleased       = false
    }

    func armReduction() {
        shouldGateReduction = true
        hasArrived          = false
        isReleased          = false
    }

    func armTemporaryMemory() {
        shouldGateTemporaryMemory = true
        hasArrived                = false
        isReleased                = false
    }

    func armStateAdmission() {
        shouldGateStateAdmission = true
        hasArrived               = false
        isReleased               = false
    }

    func armJobAdmission() {
        shouldGateJobAdmission = true
        hasArrived             = false
        isReleased             = false
    }

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

    private func reportTerminalArrival() {
        hasArrived = true
        isReleased = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        releaseContinuation?.resume()
        releaseContinuation = nil
    }

    func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) async throws -> ResourceReservation {
        let shouldGate: Bool

        switch request {
            case .temporaryMemory where shouldGateTemporaryMemory:
                shouldGateTemporaryMemory = false
                shouldGate                = true

            case .state where shouldGateStateAdmission:
                shouldGateStateAdmission = false
                shouldGate               = true

            case .job where shouldGateJobAdmission:
                shouldGateJobAdmission = false
                shouldGate             = true

            default: shouldGate = false
        }

        let reservation: ResourceReservation

        do {
            reservation = try await resourceGovernorTarget.admit(request, owner: owner)
        } catch {
            if shouldGate { reportTerminalArrival() }
            throw error
        }

        guard shouldGate else { return reservation }

        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        if isReleased { return reservation }
        await waitForRelease()
        return reservation
    }

    func release(
        _ reservationID: UUID,
        owner          : AddonID
    ) async throws {
        let shouldGate    = shouldGateRelease
        shouldGateRelease = false
        try await resourceGovernorTarget.release(reservationID, owner: owner)
        guard shouldGate else { return }

        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        await waitForRelease()
    }

    func reduceStateReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        toBytes bytes  : Int
    ) async -> Bool {
        let shouldGate      = shouldGateReduction
        shouldGateReduction = false
        let result          = await resourceGovernorTarget.reduceStateReservation(
            reservationID,
            owner  : owner,
            toBytes: bytes
        )
        guard shouldGate else { return result }

        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        if isReleased { return result }
        await waitForRelease()
        return result
    }

    func resizeStateReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        fromBytes      : Int,
        toBytes        : Int
    ) async throws -> Bool {
        let shouldGate   = shouldGateResize
        shouldGateResize = false
        let result: Bool

        do {
            result = try await resourceGovernorTarget.resizeStateReservation(
                reservationID,
                owner    : owner,
                fromBytes: fromBytes,
                toBytes  : toBytes
            )
        } catch {
            if shouldGate { reportTerminalArrival() }
            throw error
        }

        guard shouldGate else { return result }

        hasArrived = true
        arrivalContinuation?.resume()
        arrivalContinuation = nil
        if isReleased { return result }
        await waitForRelease()
        return result
    }

    func resizeDiskReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        fromBytes      : Int,
        toBytes        : Int
    ) async throws -> Bool {
        try await resourceGovernorTarget.resizeDiskReservation(
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
