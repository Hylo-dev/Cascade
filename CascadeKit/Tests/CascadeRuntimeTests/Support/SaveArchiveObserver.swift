//
//  SaveArchiveObserver.swift
//  CascadeKit
//

import CascadeContracts
import CoreGraphics
import Foundation
import ImageIO
import Testing

@testable import CascadeRuntime

/// SaveArchiveObserver gates the return of a real filesystem inventory at a chosen operation boundary.
actor SaveArchiveObserver: SwiftDataArchiveObserving {

    private var countdown : Int?
    private var hasArrived = false
    private var arrival   : CheckedContinuation<Void, Never>?
    private var resume    : CheckedContinuation<Void, Never>?

    func arm(after count: Int) {
        countdown  = count
        hasArrived = false
    }

    func waitForArrival() async {
        if !hasArrived { await withCheckedContinuation { arrival = $0 } }
    }

    func release() {
        resume?.resume()
        resume = nil
    }

    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory {
        let result = await NativeSwiftDataArchiveObserver().inventory(
            root      : root,
            descriptor: descriptor
        )

        if let countdown {
            if countdown == 0 {
                self.countdown = nil
                hasArrived     = true
                arrival?.resume()
                arrival = nil
                await withCheckedContinuation { resume = $0 }
            } else {
                self.countdown = countdown - 1
            }
        }

        return result
    }
}
