//
//  MemoryDisableSignal.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

final class MemoryDisableSignal: @unchecked Sendable {

    private let arrived = DispatchSemaphore(value: 0)

    func signal() {
        arrived.signal()
    }

    func waitForArrival() -> Bool {
        arrived.wait(timeout: .now() + 5) == .success
    }
}
