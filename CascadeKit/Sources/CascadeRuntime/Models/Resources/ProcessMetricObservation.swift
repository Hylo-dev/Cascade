//
//  ProcessMetricObservation.swift
//  CascadeKit
//

import Foundation

struct ProcessMetricObservation: Equatable, Sendable {
    let binding: ProcessMetricBinding
    let userTicks: UInt64
    let systemTicks: UInt64
    let footprintBytes: UInt64
    let window: ProcessMetricWindow
    let timebase: ProcessMetricTimebase
}
