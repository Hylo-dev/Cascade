//
//  AssetLifecycleGate.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

#if DEBUG

/// AssetLifecycleGate owns one checkpoint and one waiter. Terminal notification wakes a test
/// when the real request returns before reaching the checkpoint, avoiding a stranded waiter.
final class AssetLifecycleGate: @unchecked Sendable {
    private let condition = NSCondition()
    private var arrived = false
    private var terminal = false
    private var released = false
    private var waiter: CheckedContinuation<Bool, Never>?
    private var blocked: CheckedContinuation<Void, Never>?

    func waitForArrival() async -> Bool {
        await withCheckedContinuation { continuation in
            condition.lock()
            if arrived || terminal {
                let result = arrived
                condition.unlock()
                continuation.resume(returning: result)
            } else {
                precondition(waiter == nil)
                waiter = continuation
                condition.unlock()
            }
        }
    }

    func holdAdmission() async {
        await withCheckedContinuation { continuation in
            condition.lock()
            arrived = true
            let notify = waiter
            waiter = nil
            let alreadyReleased = released
            if !alreadyReleased { blocked = continuation }
            condition.unlock()
            notify?.resume(returning: true)
            if alreadyReleased { continuation.resume() }
        }
    }

    /// holdNative parks only the real off-main native worker, never the governor/runtime actor.
    func holdNative() {
        condition.lock()
        arrived = true
        let notify = waiter
        waiter = nil
        condition.unlock()
        notify?.resume(returning: true)
        condition.lock()
        while !released { condition.wait() }
        condition.unlock()
    }

    func release() {
        condition.lock()
        released = true
        let continuation = blocked
        blocked = nil
        condition.broadcast()
        condition.unlock()
        continuation?.resume()
    }

    func finished() {
        condition.lock()
        terminal = true
        let notify = waiter
        waiter = nil
        let result = arrived
        condition.unlock()
        notify?.resume(returning: result)
    }
}

#endif
