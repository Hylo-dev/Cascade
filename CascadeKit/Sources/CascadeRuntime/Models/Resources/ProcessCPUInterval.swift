//
//  ProcessCPUInterval.swift
//  CascadeKit
//

import Foundation

struct ProcessCPUInterval: Equatable, Sendable {
    let cpuNanoseconds: UInt64
    let elapsedNanoseconds: UInt64
    let previousWindow: ProcessMetricWindow
    let currentWindow: ProcessMetricWindow
}
