//
//  CoordinatorResourceGate.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

/// CoordinatorResourceGate delays one real governor result to exercise coordinator reentrancy.
actor CoordinatorResourceGate: RuntimeResourceAccess {
    enum Point {
        case stateAdmission
        case temporaryAdmission
    }

    nonisolated let resourceGovernorTarget: ResourceGovernor
    private var point     : Point?
    private var hasArrived = false
    private var arrival   : CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Never>?

    init(_ governor: ResourceGovernor) { resourceGovernorTarget = governor }

    func arm(_ point: Point) {
        self.point = point
        hasArrived = false
    }

    func wait() async {
        if hasArrived { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func resume() {
        completion?.resume()
        completion = nil
    }

    private func hold(_ candidate: Point) async {
        guard point == candidate else { return }
        point = nil
        hasArrived = true
        arrival?.resume()
        arrival = nil
        await withCheckedContinuation { completion = $0 }
    }

    func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) async throws -> ResourceReservation {
        let reservation = try await resourceGovernorTarget.admit(
            request,
            owner: owner
        )
        switch request {
        case .state:
            await hold(.stateAdmission)
        case .temporaryMemory:
            await hold(.temporaryAdmission)
        default:
            break
        }
        return reservation
    }

    func release(
        _ reservationID: UUID,
        owner          : AddonID
    ) async throws {
        try await resourceGovernorTarget.release(
            reservationID,
            owner: owner
        )
    }

    func reduceStateReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        toBytes        : Int
    ) async -> Bool {
        await resourceGovernorTarget.reduceStateReservation(
            reservationID,
            owner  : owner,
            toBytes: toBytes
        )
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
}
