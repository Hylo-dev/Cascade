//
//  CrashDemandGate.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

actor CrashDemandGate {
    private let pauseOnCall: Int
    private var calls = 0
    private var arrived = false
    private var released = false
    private var arrivalWaiter: CheckedContinuation<Bool, Never>?
    private var releaseWaiter: CheckedContinuation<Void, Never>?

    init(pauseOnCall: Int = 1) {
        self.pauseOnCall = pauseOnCall
    }

    func pause() async {
        calls += 1
        guard calls == pauseOnCall else { return }
        arrived = true
        arrivalWaiter?.resume(returning: true)
        arrivalWaiter = nil
        if !released {
            await withCheckedContinuation { releaseWaiter = $0 }
        }
    }

    func waitForArrival() async -> Bool {
        if arrived || released { return arrived }
        return await withCheckedContinuation { arrivalWaiter = $0 }
    }

    func release() {
        released = true
        arrivalWaiter?.resume(returning: arrived)
        arrivalWaiter = nil
        releaseWaiter?.resume()
        releaseWaiter = nil
    }
}
