//
//  CPUAdmissionReadSource.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

/// CPUAdmissionReadSource produces a real coordinator baseline, one overspend,
/// then zero-work intervals so the runtime must rely on measured positive credit.
final class CPUAdmissionReadSource: @unchecked Sendable {

    private let lock      = NSLock()
    private let binding  : ProcessMetricBinding
    private let userTicks: [UInt64?]

    private var count = 0

    init(
        binding  : ProcessMetricBinding,
        userTicks: [UInt64?] = [0, 150_000_000]
    ) {
        self.binding   = binding
        self.userTicks = userTicks
    }

    func read(_ binding: ProcessMetricBinding) -> ProcessMetricReadResult {
        lock.withLock {
            guard binding == self.binding else { return .unavailable(.identityMismatch) }

            count += 1
            let index = count - 1
            guard index < userTicks.count, let ticks = userTicks[index] else {
                return .unavailable(.readFailed(5))
            }

            let start = UInt64(count) * 100
            return .sample(ProcessMetricObservation(
                binding       : binding,
                userTicks     : ticks,
                systemTicks   : 0,
                footprintBytes: 4_096,
                window        : ProcessMetricWindow(startTicks: start, endTicks: start + 1),
                timebase      : ProcessMetricTimebase(numer: 1, denom: 1)
            ))
        }
    }
}
