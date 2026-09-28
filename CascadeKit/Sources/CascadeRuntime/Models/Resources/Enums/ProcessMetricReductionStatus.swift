//
//  ProcessMetricReductionStatus.swift
//  CascadeKit
//

import Foundation

enum ProcessMetricReductionStatus: Equatable, Sendable {
    case baseline, interval
    case reset(ProcessMetricFailure), unavailable(ProcessMetricFailure), invalid(ProcessMetricFailure)
}
