//
//  InvocationRouteGate.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK
@testable import CascadeRuntime

/// InvocationRouteGate holds one arrival and one release, joined by the operation that owns
/// the paid workspace.
actor InvocationRouteGate {

    private var arrived  = false
    private var released = false

    var hasArrived: Bool { arrived }

    private var arrival      : CheckedContinuation<Void, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func pause() async {
        arrived = true
        arrival?.resume()
        arrival = nil
        if !released { await withCheckedContinuation { releaseWaiter = $0 } }
    }

    func wait() async { if !arrived { await withCheckedContinuation { arrival = $0 } } }

    func release() {
        released = true
        releaseWaiter?.resume()
        releaseWaiter = nil
        arrival?.resume()
        arrival = nil
    }
}
