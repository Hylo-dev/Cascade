//
//  ProcessMetricBatch.swift
//  CascadeKit
//

/// ProcessMetricBatch is the bounded result of one serialized acquisition pass.
struct ProcessMetricBatch: Equatable, Sendable {

    let reason       : ProcessMetricSampleReason
    let sampledAt    : Duration
    let samples      : [ProcessMetricCoordinatedSample]
    let cpuAccounting: [ProcessMetricCPUAccounting]
}
