//
//  AssetPrivacyPartition.swift
//  CascadeKit
//

import Foundation

/// AssetPrivacyPartition identifies immutable host-assigned asset sharing boundaries.
/// These labels are not wire grants or substitutes for service/account authorization.
/// Document privacy remains redaction metadata and cannot select this partition.
enum AssetPrivacyPartition: Hashable, Sendable {
    case addonOwned
    case isolated(UUID)
}
