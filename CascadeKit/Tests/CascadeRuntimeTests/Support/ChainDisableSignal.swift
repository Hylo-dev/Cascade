//
//  ChainDisableSignal.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Foundation
import Testing
@testable import CascadeRuntime

final class ChainDisableSignal: @unchecked Sendable {
    private let arrived = DispatchSemaphore(value: 0)

    func signal() { arrived.signal() }

    func waitForArrival() -> Bool {
        arrived.wait(timeout: .now() + 5) == .success
    }
}
