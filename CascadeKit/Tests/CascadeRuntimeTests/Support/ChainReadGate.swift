//
//  ChainReadGate.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Foundation
import Testing
@testable import CascadeRuntime

final class ChainReadGate: @unchecked Sendable {
    private let arrived = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    func pause() {
        arrived.signal()
        guard released.wait(timeout: .now() + 5) == .success else {
            Issue.record("The delegated CPU reader was not released in time.")
            return
        }
    }

    func waitForArrival() -> Bool {
        arrived.wait(timeout: .now() + 5) == .success
    }

    func release() { released.signal() }
}
