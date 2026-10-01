//
//  StorageDrainObservation.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeAddonSDK

final class StorageDrainObservation: @unchecked Sendable {

    private let lock     = NSLock()
    private var entered : Set<Int> = []
    private var returned: Set<Int> = []
    private var waiter  : CheckedContinuation<Void, Never>?

    var returnedCount: Int { lock.withLock { returned.count } }

    func enter(_ caller: Int) {
        let completion = lock.withLock { () -> CheckedContinuation<Void, Never>? in
            entered.insert(caller)
            guard entered.count == 3 else { return nil }

            defer { waiter = nil }

            return waiter
        }

        completion?.resume()
    }

    func returned(_ caller: Int) { lock.withLock { _ = returned.insert(caller) } }

    func waitForAll() async {
        await withCheckedContinuation { continuation in
            let ready = lock.withLock {
                if entered.count == 3 { return true }

                waiter = continuation

                return false
            }

            if ready { continuation.resume() }
        }
    }
}
