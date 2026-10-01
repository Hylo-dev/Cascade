//
//  StorageTestGate.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

/// StorageTestGate is one held point and one arrival waiter, without queues, polling or
/// cancellation disposal.
actor StorageTestGate {
    private var arrived = false
    private var released = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var resume: CheckedContinuation<Void, Never>?

    func hold() async {
        arrived = true
        arrival?.resume(); arrival = nil
        if !released { await withCheckedContinuation { resume = $0 } }
    }
    func wait() async {
        if !arrived { await withCheckedContinuation { arrival = $0 } }
    }
    func release() {
        released = true
        resume?.resume(); resume = nil
    }
}
