//
//  ProcessMetricDelegatedAttribution.swift
//  CascadeKit
//

import Foundation

/// ProcessMetricDelegatedAttribution names host-verified consumers whose
/// canonical service activity overlapped this exact physical binding's interval.
/// The coordinator validates identity and bounds, but cannot prove that overlap.
struct ProcessMetricDelegatedAttribution: Equatable, Sendable {
    let binding  : ProcessMetricBinding
    let consumers: [VerifiedAddonIdentity]
}
