//
//  AssetLifecycleTestObserver.swift
//  CascadeKit
//

import Foundation

#if DEBUG

/// AssetLifecycleTestObserver observes real operations; it cannot supply authorization,
/// reservations, decoded pixels or refund decisions. Task-local scope also covers both
/// runtime assembler construction paths without mutable per-runtime test configuration.
protocol AssetLifecycleTestObserver: Sendable {

    var governor: ResourceGovernor { get }

    func admittedTransfer(
        reservationID: UUID,
        binding      : AssetTransferBinding
    ) async

    func decodeEntered()
    func decodeReservationEntered()
    func nativeDrawCompleted()
    func nativeScopeReturned()
    func aliasCommitted()
}

#endif
