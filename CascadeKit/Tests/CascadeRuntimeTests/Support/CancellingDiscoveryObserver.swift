//
//  CancellingDiscoveryObserver.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing

@testable import CascadeRuntime

struct CancellingDiscoveryObserver: SwiftDataArchiveObserving {

    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory {
        let observed = SwiftDataArchiveDirectory.inventory(root: root, descriptor: descriptor)
        withUnsafeCurrentTask { $0?.cancel() }

        return observed
    }
}
