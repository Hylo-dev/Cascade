//
//  KeyedResourceGate.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

/// KeyedResourceGate delays one real governor result, never admission or disk I/O itself.
actor KeyedResourceGate: RuntimeResourceAccess {

    enum Point {

        case temporary
        case diskAdmission
        case diskResize
        case release
    }

    nonisolated let resourceGovernorTarget: ResourceGovernor

    private var point         : Point?
    private var remainingSkips = 0
    private var arrived        = false
    private var released       = false
    private var arrival       : CheckedContinuation<Void, Never>?
    private var completion    : CheckedContinuation<Void, Never>?

    init(_ governor: ResourceGovernor) { resourceGovernorTarget = governor }

    /// arm skips only a bounded number of matching real returns, distinguishing stage from commit cleanup.
    func arm(
        _ point : Point,
        skipping: Int = 0
    ) {
        precondition((0...8).contains(skipping))

        self.point     = point
        remainingSkips = skipping
        arrived        = false
        released       = false
    }

    func wait() async {
        if arrived { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func resume() {
        released = true
        completion?.resume()
        completion = nil
    }

    private func hold(_ candidate: Point) async {
        guard point == candidate else { return }

        if remainingSkips > 0 {
            remainingSkips -= 1
            return
        }

        point   = nil
        arrived = true
        arrival?.resume()
        arrival = nil
        if released { return }

        await withCheckedContinuation { completion = $0 }
    }

    func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) async throws -> ResourceReservation {
        let result = try await resourceGovernorTarget.admit(request, owner: owner)

        switch request {
            case .temporaryMemory: await hold(.temporary)
            case .diskState, .diskCache: await hold(.diskAdmission)
            default: break
        }

        return result
    }

    func release(
        _ reservationID: UUID,
        owner          : AddonID
    ) async throws {
        try await resourceGovernorTarget.release(reservationID, owner: owner)
        await hold(.release)
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
        let result = try await resourceGovernorTarget.resizeDiskReservation(
            reservationID,
            owner    : owner,
            fromBytes: fromBytes,
            toBytes  : toBytes
        )
        await hold(.diskResize)

        return result
    }
}
