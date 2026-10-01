//
//  SwiftDataArchiveInventory.swift
//  CascadeKit
//

/// SwiftDataArchiveInventory reports known file lengths even when a scan cannot finish.
/// An incomplete observation can increase a ledger, but cannot prove any retained bytes gone.
struct SwiftDataArchiveInventory: Sendable {

    let bytes            : Int
    let isComplete       : Bool
    let hasUnsafeEntries : Bool
    let hasUnknownEntries: Bool

    var permitsFrameworkAccess: Bool {
        isComplete && !hasUnsafeEntries && !hasUnknownEntries
    }
}
