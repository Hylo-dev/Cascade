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

    func workspaceResizeMemoryReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        fromBytes       : Int,
        toBytes         : Int
    ) async throws -> Bool

    func workspaceAdmitObservedDisk(
        bytes                : Int,
        owner                : AddonID,
        retainedMetadataBytes: Int
    ) async throws -> ObservedDiskToken

    func workspaceGrowObservedDisk(
        _ token  : ObservedDiskToken,
        owner    : AddonID,
        fromBytes: Int,
        toBytes  : Int
    ) async throws -> Bool

    func workspaceReconcileObservedDisk(
        _ token      : ObservedDiskToken,
        owner        : AddonID,
        fromBytes    : Int,
        measuredBytes: Int
    ) async throws -> Bool
}

extension RuntimeResourceAccess {
    func workspaceResizeMemoryReservation(
        _ reservationID: UUID,
        owner           : AddonID,
        fromBytes       : Int,
        toBytes         : Int
    ) async throws -> Bool {
        try await resourceGovernorTarget.resizeMemoryReservation(
            reservationID,
            owner    : owner,
            fromBytes: fromBytes,
            toBytes  : toBytes
        )
    }

    func workspaceAdmitObservedDisk(
        bytes                : Int,
        owner                : AddonID,
        retainedMetadataBytes: Int
    ) async throws -> ObservedDiskToken {
        try await resourceGovernorTarget.admitObservedDisk(
            bytes                : bytes,
            owner                : owner,
            retainedMetadataBytes: retainedMetadataBytes
        )
    }

    func workspaceGrowObservedDisk(
        _ token  : ObservedDiskToken,
        owner    : AddonID,
        fromBytes: Int,
        toBytes  : Int
    ) async throws -> Bool {
        try await resourceGovernorTarget.growObservedDisk(
            token,
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
        try await resourceGovernorTarget.reconcileObservedDisk(
            token,
            owner        : owner,
            fromBytes    : fromBytes,
            measuredBytes: measuredBytes
        )
    }
}
