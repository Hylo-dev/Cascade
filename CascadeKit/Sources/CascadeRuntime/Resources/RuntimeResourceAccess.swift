//
//  RuntimeResourceAccess.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// RuntimeResourceAccess is the runtime's narrow forwarding boundary to its canonical governor.
/// Production uses ResourceGovernor directly; test wrappers may delay only the return of a
/// completed real mutation so actor reentrancy can be exercised without fake reservations.
protocol RuntimeResourceAccess: Sendable {
    var resourceGovernorTarget: ResourceGovernor { get }

    func admit(
        _ request: ResourceRequest,
        owner    : AddonID
    ) async throws -> ResourceReservation

    func release(
        _ reservationID: UUID,
        owner           : AddonID
    ) async throws

    func reduceStateReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        toBytes bytes   : Int
    ) async -> Bool

    func resizeStateReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        fromBytes       : Int,
        toBytes         : Int
    ) async throws -> Bool

    func resizeDiskReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        fromBytes       : Int,
        toBytes         : Int
    ) async throws -> Bool

}

extension ResourceGovernor: RuntimeResourceAccess {
    nonisolated var resourceGovernorTarget: ResourceGovernor { self }
}

