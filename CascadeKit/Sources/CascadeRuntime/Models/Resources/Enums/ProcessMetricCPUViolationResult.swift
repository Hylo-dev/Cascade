//
//  ProcessMetricCPUViolationResult.swift
//  CascadeKit
//

import Foundation

/// ProcessMetricCPUViolationResult classifies only CPU newly observed in one batch.
/// It intentionally holds no history: health policy decides what to retain later.
enum ProcessMetricCPUViolationResult: Equatable, Sendable {
    case noNewViolation
    case moderate
    case unavailable
}
