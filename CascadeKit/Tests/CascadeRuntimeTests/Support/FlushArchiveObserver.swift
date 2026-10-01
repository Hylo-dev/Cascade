//
//  FlushArchiveObserver.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

/// FlushArchiveObserver forwards native filesystem inventory and parks one selected return.
/// The bounded gate exposes the real postcommit boundary without substituting storage results.
actor FlushArchiveObserver: SwiftDataArchiveObserving {

    private var countdown: Int?
    private var arrived   = false
    private var arrival  : CheckedContinuation<Void, Never>?
    private var resume   : CheckedContinuation<Void, Never>?

    func arm(after count: Int) {
        countdown = count
        arrived   = false
    }

    func waitForArrival() async {
        if !arrived { await withCheckedContinuation { arrival = $0 } }
    }

    func release() {
        resume?.resume()
        resume = nil
    }

    /// inventory preserves the native observation and suspends only its selected return.
    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory {
        let inventory = await NativeSwiftDataArchiveObserver().inventory(
            root      : root,
            descriptor: descriptor
        )

        if let countdown {
            if countdown == 0 {
                self.countdown = nil
                arrived        = true
                arrival?.resume()
                arrival = nil
                await withCheckedContinuation { resume = $0 }
            } else {
                self.countdown = countdown - 1
            }
        }

        return inventory
    }
}
