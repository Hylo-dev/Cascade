//
//  ProcessMetricSampleReason.swift
//  CascadeKit
//

/// ProcessMetricSampleReason records why the host requested one common batch.
enum ProcessMetricSampleReason: Equatable, Sendable {

    case periodic
    case jobBoundary
    case memoryPressure
}
