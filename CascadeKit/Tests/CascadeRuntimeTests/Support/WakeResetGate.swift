//
//  WakeResetGate.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

/// WakeResetGate has finite waits on both sides of a deterministic read or
/// post-reset checkpoint; failure releases the blocked worker before it hangs.
final class WakeResetGate: @unchecked Sendable {

    private let arrived  = DispatchSemaphore(value: 0)
    private let released = DispatchSemaphore(value: 0)

    func pause() {
        arrived.signal()
        if released.wait(timeout: .now() + 5) == .timedOut {
            Issue.record("A metric wake checkpoint was not released within five seconds.")
        }
    }

    func waitForArrival() -> Bool {
        arrived.wait(timeout: .now() + 5) == .success
    }

    func release() {
        released.signal()
    }
}
