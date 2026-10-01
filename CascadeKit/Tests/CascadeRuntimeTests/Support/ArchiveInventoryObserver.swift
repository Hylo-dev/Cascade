//
//  ArchiveInventoryObserver.swift
//  CascadeKit
//

import CascadeContracts
import Darwin
import Foundation
import Testing
@testable import CascadeRuntime

/// ArchiveInventoryObserver gates only complete native scans and can conservatively mark one incomplete.
actor ArchiveInventoryObserver: SwiftDataArchiveObserving {

    private var gatedName     : String?
    private var incompleteName: String?
    private var counts        : [String: Int] = [:]
    private var arrived        = false
    private var arrival       : CheckedContinuation<Void, Never>?
    private var completion    : CheckedContinuation<Void, Never>?

    func markIncomplete(_ name: String?) { incompleteName = name }

    func count(_ name: String) -> Int { counts[name, default: 0] }

    func arm(_ name: String) {
        gatedName = name
        arrived   = false
    }

    func wait() async {
        if arrived { return }

        await withCheckedContinuation { arrival = $0 }
    }

    func resume() {
        completion?.resume()
        completion = nil
    }

    /// inventory always measures native files before a deliberate delay or conservative incomplete flag.
    func inventory(
        root      : URL,
        descriptor: Int32
    ) async -> SwiftDataArchiveInventory {
        let observation = SwiftDataArchiveDirectory.inventory(root: root, descriptor: descriptor)
        let name        = root.lastPathComponent
        counts[name, default: 0] += 1

        if gatedName == name {
            gatedName = nil
            arrived   = true
            arrival?.resume()
            arrival = nil
            await withCheckedContinuation { completion = $0 }
        }

        if incompleteName == name {
            return SwiftDataArchiveInventory(
                bytes            : observation.bytes,
                isComplete       : false,
                hasUnsafeEntries : observation.hasUnsafeEntries,
                hasUnknownEntries: observation.hasUnknownEntries
            )
        }

        return observation
    }
}
