//
//  ProcessMetricCoordinatedSample.swift
//  CascadeKit
//

import Foundation

/// ProcessMetricCoordinatedSample pairs a physical reduction with the exact
/// direct and delegated owners charged or marked incomplete for that row.
struct ProcessMetricCoordinatedSample: Equatable, Sendable {
    let binding      : ProcessMetricBinding
    let reduction    : ProcessMetricReduction
    let chargedOwners: [VerifiedAddonIdentity]
}
