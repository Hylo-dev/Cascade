//
//  ProcessMetricReadResult.swift
//  CascadeKit
//

import Foundation

enum ProcessMetricReadResult: Equatable, Sendable {
    case sample(ProcessMetricObservation)
    case unavailable(ProcessMetricFailure)
}
