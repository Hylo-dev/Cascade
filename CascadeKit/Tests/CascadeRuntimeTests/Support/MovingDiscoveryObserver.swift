//
//  MovingDiscoveryObserver.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing

@testable import CascadeRuntime

struct MovingDiscoveryObserver: SwiftDataArchiveObserving {
    let parent: URL
    let parked: URL

    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory {
        let observed = SwiftDataArchiveDirectory.inventory(
            root      : root,
            descriptor: descriptor
        )
        try? FileManager.default.moveItem(
            at: parent,
            to: parked
        )
        return observed
    }
}
