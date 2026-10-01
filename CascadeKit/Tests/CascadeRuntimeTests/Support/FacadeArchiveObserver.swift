//
//  FacadeArchiveObserver.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CascadeRuntime

/// FacadeArchiveObserver delays a chosen real observation without omitting measured file bytes.
actor FacadeArchiveObserver: SwiftDataArchiveObserving {
    private var countdown: Int?
    private var arrived = false
    private var arrival: CheckedContinuation<Void, Never>?
    private var completion: CheckedContinuation<Void, Never>?

    func arm(after count: Int) {
        countdown = count
        arrived = false
    }
    func wait() async {
        if arrived { return }
        await withCheckedContinuation { arrival = $0 }
    }
    func resume() {
        completion?.resume()
        completion = nil
    }
    /// inventory measures the real held root before delaying its return at the requested boundary.
    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory {
        let observed = SwiftDataArchiveDirectory.inventory(
            root      : root,
            descriptor: descriptor
        )
        if let countdown {
            if countdown == 0 {
                self.countdown = nil
                arrived = true
                arrival?.resume()
                arrival = nil
                await withCheckedContinuation { completion = $0 }
            } else {
                self.countdown = countdown - 1
            }
        }
        return observed
    }
}
