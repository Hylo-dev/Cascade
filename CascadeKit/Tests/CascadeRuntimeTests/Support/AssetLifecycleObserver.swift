//
//  AssetLifecycleObserver.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

#if DEBUG

/// AssetLifecycleObserver counts real entries and can hold exactly one selected checkpoint.
/// All authority, pixels and accounting come from the production operation being observed.
final class AssetLifecycleObserver: AssetLifecycleTestObserver, @unchecked Sendable {
    enum Point: String, CaseIterable, Sendable { case admission, native, none }
    struct Snapshot: Sendable {
        var reservationID: UUID?
        var binding: AssetTransferBinding?
        var admissions = 0
        var decodeEntries = 0
        var decodeReservations = 0
        var nativeDraws = 0
        var nativeReturns = 0
        var aliasCommits = 0
    }

    let governor: ResourceGovernor
    let point: Point
    let gate = AssetLifecycleGate()
    private let lock = NSLock()
    private var value = Snapshot()

    init(governor: ResourceGovernor, point: Point) {
        self.governor = governor
        self.point = point
    }

    func snapshot() -> Snapshot { lock.withLock { value } }

    func admittedTransfer(reservationID: UUID, binding: AssetTransferBinding) async {
        lock.withLock {
            value.reservationID = reservationID
            value.binding = binding
            value.admissions += 1
        }
        if point == .admission { await gate.holdAdmission() }
    }

    func decodeEntered() { lock.withLock { value.decodeEntries += 1 } }
    func decodeReservationEntered() { lock.withLock { value.decodeReservations += 1 } }
    func nativeDrawCompleted() {
        lock.withLock { value.nativeDraws += 1 }
        if point == .native { gate.holdNative() }
    }
    func nativeScopeReturned() { lock.withLock { value.nativeReturns += 1 } }
    func aliasCommitted() { lock.withLock { value.aliasCommits += 1 } }
}

#endif
