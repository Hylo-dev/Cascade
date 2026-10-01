//
//  BridgeExchangeGate.swift
//  CascadeKit
//

import CascadeAddonSDK
import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

/// BridgeExchangeGate suspends exactly one staged bridge exchange at a deterministic point.
///
/// It holds one optional continuation pair, no queue and no history. `close` releases the held
/// exchange before awaiting it, so a genuine close never depends on a sleep, a poll or an
/// external timer. The flags make arming and release order-independent.
actor BridgeExchangeGate {

    private var isArmed    = false
    private var hasArrived = false
    private var isReleased = false
    private var arrival   : CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Never>?

    func arm() {
        isArmed    = true
        hasArrived = false
        isReleased = false
    }

    func arrivalPoint() async {
        guard isArmed else { return }

        isArmed    = false
        hasArrived = true
        arrival?.resume()
        arrival = nil

        if isReleased { return }
        await withCheckedContinuation { completion = $0 }
    }

    func waitForArrival() async {
        if hasArrived { return }
        await withCheckedContinuation { arrival = $0 }
    }

    func release() {
        isReleased = true
        completion?.resume()
        completion = nil
    }
}
