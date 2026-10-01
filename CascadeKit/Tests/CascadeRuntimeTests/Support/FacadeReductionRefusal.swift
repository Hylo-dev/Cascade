//
//  FacadeReductionRefusal.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

/// FacadeReductionRefusal injects one failed refund while every successful operation uses the real governor.
actor FacadeReductionRefusal: RuntimeResourceAccess {

    nonisolated let resourceGovernorTarget: ResourceGovernor

    private let gate            : GatedRuntimeResourceAccess
    private var refusesReduction = false

    init(gate: GatedRuntimeResourceAccess) {
        self.gate              = gate
        resourceGovernorTarget = gate.resourceGovernorTarget
    }

    func refuseNextReduction() { refusesReduction = true }

    func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) async throws -> ResourceReservation {
        try await gate.admit(request, owner: owner)
    }

    func release(
        _ reservationID: UUID,
        owner          : AddonID
    ) async throws {
        try await gate.release(reservationID, owner: owner)
    }

    /// reduceStateReservation may refuse one refund; accepted refunds always reach the real governor.
    func reduceStateReservation(
        _ reservationID: UUID,
        owner          : AddonID,
        toBytes        : Int
    ) async -> Bool {
        if refusesReduction {
            refusesReduction = false
            return false
        }

        return await gate.reduceStateReservation(
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
        try await gate.resizeStateReservation(
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
        try await gate.resizeDiskReservation(
            reservationID,
            owner    : owner,
            fromBytes: fromBytes,
            toBytes  : toBytes
        )
    }
}
