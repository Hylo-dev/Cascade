//
//  ProcessMetricCPUAccountingResult.swift
//  CascadeKit
//

/// ProcessMetricCPUAccountingResult reports whether every owned row contributed
/// a committed interval to one batch, without exposing stale credit on gaps.
enum ProcessMetricCPUAccountingResult: Equatable, Sendable {

    case complete(AddonCPUBudget.Snapshot)
    case incomplete
    case accountingFailed
}
