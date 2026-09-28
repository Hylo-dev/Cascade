//
//  ProcessMetricSampleReason.swift
//  CascadeKit
//

import Foundation

/// ProcessMetricSampleReason records why the host requested one common batch.
enum ProcessMetricSampleReason: Equatable, Sendable {
    case periodic, jobBoundary, memoryPressure
}
