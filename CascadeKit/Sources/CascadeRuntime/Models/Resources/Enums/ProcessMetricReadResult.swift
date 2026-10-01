//
//  ProcessMetricReadResult.swift
//  CascadeKit
//

enum ProcessMetricReadResult: Equatable, Sendable {

    case sample     (ProcessMetricObservation)
    case unavailable(ProcessMetricFailure)
}
