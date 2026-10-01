//
//  ConsumerMetricReadSource.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

final class ConsumerMetricReadSource: @unchecked Sendable {
    private let lock = NSLock()
    private let binding: ProcessMetricBinding
    private var count = 0

    init(binding: ProcessMetricBinding) {
        self.binding = binding
    }

    func read(_ actual: ProcessMetricBinding) -> ProcessMetricReadResult {
        lock.withLock {
            guard actual == binding else { return .unavailable(.identityMismatch) }
            count += 1
            return .sample(ProcessMetricObservation(
                binding       : binding,
                userTicks     : count == 1 ? 0 : 150_000_000,
                systemTicks   : 0,
                footprintBytes: 4_096,
                window        : ProcessMetricWindow(
                    startTicks: UInt64(count) * 100 + 100,
                    endTicks  : UInt64(count) * 100 + 101
                ),
                timebase      : ProcessMetricTimebase(numer: 1, denom: 1)
            ))
        }
    }
}
