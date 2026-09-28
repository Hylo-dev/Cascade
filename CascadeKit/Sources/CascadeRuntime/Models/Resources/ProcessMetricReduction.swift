//
//  ProcessMetricReduction.swift
//  CascadeKit
//

import Foundation

/// ProcessMetricReduction is the outcome of one reduction; a current valid footprint can survive
/// CPU-only arithmetic failure. Neither a baseline nor an unavailable/reset interval represents
/// measured zero CPU use.
struct ProcessMetricReduction: Equatable, Sendable {
    let status: ProcessMetricReductionStatus
    let footprintBytes: UInt64?
    let interval: ProcessCPUInterval?
}
