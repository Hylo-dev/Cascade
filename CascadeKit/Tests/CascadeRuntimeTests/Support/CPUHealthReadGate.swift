//
//  CPUHealthReadGate.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

/// CPUHealthReadGate pauses only the second native read with a bounded timeout.
/// Tests can revoke runtime authority while the coordinator owns a real reduction.
final class CPUHealthReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private let arrived = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)
    private var readCount = 0

    func pauseOnSecondRead() {
        let shouldPause = lock.withLock {
            readCount += 1
            return readCount == 2
        }
        guard shouldPause else { return }
        arrived.signal()
        _ = released.wait(timeout: .now() + 5)
    }

    func waitForArrival() -> Bool {
        arrived.wait(timeout: .now() + 5) == .success
    }

    func release() {
        released.signal()
    }
}
