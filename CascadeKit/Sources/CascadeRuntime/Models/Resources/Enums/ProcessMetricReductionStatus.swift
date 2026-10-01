//
//  ProcessMetricReductionStatus.swift
//  CascadeKit
//

enum ProcessMetricReductionStatus: Equatable, Sendable {

    case baseline
    case interval
    case reset      (ProcessMetricFailure)
    case unavailable(ProcessMetricFailure)
    case invalid    (ProcessMetricFailure)
}
