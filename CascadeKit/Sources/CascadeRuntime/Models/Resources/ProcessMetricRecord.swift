//
//  ProcessMetricRecord.swift
//  CascadeKit
//

import Foundation

/// ProcessMetricRecord holds values extracted only from a successful public v0 read. CPU fields
/// are Mach ticks; footprint is bytes. A failed read cannot carry a record of apparent zeros.
struct ProcessMetricRecord: Equatable, Sendable {
    let birthAbsoluteTicks: UInt64
    let executableUUID: UUID
    let userTicks: UInt64
    let systemTicks: UInt64
    let footprintBytes: UInt64
    let exitAbsoluteTicks: UInt64
}
