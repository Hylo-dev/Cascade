//
//  SwiftDataArchiveObserving.swift
//  CascadeKit
//

import Foundation

/// SwiftDataArchiveObserving confines test delays to real filesystem observations.
/// Implementations must inventory the held root; successful test observations may add
/// test-owned files or conservatively increase measured bytes, never omit actual files.
protocol SwiftDataArchiveObserving: Sendable {

    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory
}
