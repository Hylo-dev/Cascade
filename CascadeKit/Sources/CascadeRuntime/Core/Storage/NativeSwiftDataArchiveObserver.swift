//
//  NativeSwiftDataArchiveObserver.swift
//  CascadeKit
//

import Darwin
import Foundation

/// NativeSwiftDataArchiveObserver performs bounded descriptor-relative scans off MainActor.
struct NativeSwiftDataArchiveObserver: SwiftDataArchiveObserving {
    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory {
        SwiftDataArchiveDirectory.inventory(
            root      : root,
            descriptor: descriptor
        )
    }
}
