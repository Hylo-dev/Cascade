//
//  MemoryReadGate.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

final class MemoryReadGate: @unchecked Sendable {
    private let arrived = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    func pause() {
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
