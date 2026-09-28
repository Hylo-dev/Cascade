//
//  ProcessMetricCPUAccounting.swift
//  CascadeKit
//

import Foundation

/// ProcessMetricCPUAccounting pairs one verified owner with its final batch result.
struct ProcessMetricCPUAccounting: Equatable, Sendable {
    let owner        : VerifiedAddonIdentity
    let result       : ProcessMetricCPUAccountingResult
    let classification: ProcessMetricCPUViolationResult

    init(
        owner         : VerifiedAddonIdentity,
        result        : ProcessMetricCPUAccountingResult,
        classification: ProcessMetricCPUViolationResult = .unavailable
    ) {
        self.owner          = owner
        self.result         = result
        self.classification = classification
    }
}
