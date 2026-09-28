//
//  SwiftDataArchiveInventoryStatus.swift
//  CascadeKit
//

import Foundation

/// SwiftDataArchiveInventoryStatus separates reconciled directory inventory from model validity.
enum SwiftDataArchiveInventoryStatus: Equatable, Sendable {
    case unobserved
    case absent
    case complete
    case blocked
}
