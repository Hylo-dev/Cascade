//
//  CPURegistrationCheckpoint.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

/// CPURegistrationCheckpoint gates the post-register actor hop for at most five
/// seconds, so a failed fixture cannot strand the suite on a continuation.
final class CPURegistrationCheckpoint: @unchecked Sendable {

    private let arrived  = DispatchSemaphore(value: 0)
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
