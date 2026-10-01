//
//  MetricsDeadlineReadSource.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

final class MetricsDeadlineReadSource: @unchecked Sendable {
    private let lock = NSLock()
    private var ticks: [UInt64]
    private var count = 0
    private var windowIndex: UInt64 = 0

    var readCount: Int {
        lock.withLock { count }
    }

    init(ticks: [UInt64]) {
        self.ticks = ticks
    }

    func read(_ binding: ProcessMetricBinding) -> ProcessMetricReadResult {
        lock.withLock {
            count += 1
            windowIndex += 1
            let tick = ticks.isEmpty ? 0 : ticks.removeFirst()
            return .sample(ProcessMetricObservation(
                binding       : binding,
                userTicks     : tick,
                systemTicks   : 0,
                footprintBytes: 4_096,
                window        : ProcessMetricWindow(
                    startTicks: 200 + windowIndex,
                    endTicks  : 201 + windowIndex
                ),
                timebase      : ProcessMetricTimebase(numer: 1, denom: 1)
            ))
        }
    }
}
