//
//  ShutdownEntryClock.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import Testing

@testable import CascadeRuntime

/// ShutdownEntryClock parks one synchronous runtime actor entry at a native condition variable.
/// This test-only seam has no sleep or production hook; the test always releases the held entry.
final class ShutdownEntryClock: RuntimeClock, @unchecked Sendable {

    private let condition = NSCondition()
    private let instant  : RuntimeInstant
    private var armed     = false
    private var arrived   = false
    private var released  = false
    private var arrival  : CheckedContinuation<Void, Never>?

    init(instant: RuntimeInstant) { self.instant = instant }

    func arm() {
        condition.lock()
        armed    = true
        released = false
        arrived  = false
        condition.unlock()
    }

    func now() -> RuntimeInstant {
        condition.lock()
        if armed {
            armed   = false
            arrived = true
            arrival?.resume()
            arrival = nil
            while !released { condition.wait() }
        }

        condition.unlock()

        return instant
    }

    func waitForArrival() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                condition.lock()
                if arrived || released { continuation.resume() } else { arrival = continuation }
                condition.unlock()
            }
        } onCancel: {
            self.release()
        }
    }

    func release() {
        condition.lock()
        released = true
        arrival?.resume()
        arrival = nil
        condition.broadcast()
        condition.unlock()
    }
}
