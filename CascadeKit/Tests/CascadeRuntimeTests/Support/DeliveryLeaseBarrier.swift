//
//  DeliveryLeaseBarrier.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

actor DeliveryLeaseBarrier {
    private var suspended = false
    private var enteredWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    func suspend() async {
        suspended = true
        for waiter in enteredWaiters { waiter.resume() }
        enteredWaiters = []
        await withCheckedContinuation { releaseWaiter = $0 }
    }

    func waitUntilSuspended() async {
        if suspended { return }
        await withCheckedContinuation { enteredWaiters.append($0) }
    }

    func resume() {
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
