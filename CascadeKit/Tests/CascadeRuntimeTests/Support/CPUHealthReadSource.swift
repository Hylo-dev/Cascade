//
//  CPUHealthReadSource.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

final class CPUHealthReadSource: @unchecked Sendable {

    private let lock   = NSLock()
    private var queued: [UUID: [ProcessMetricReadResult]]
    private let gate  : CPUHealthReadGate?

    init(
        _ queued: [UUID: [ProcessMetricReadResult]],
        gate    : CPUHealthReadGate? = nil
    ) {
        self.queued = queued
        self.gate   = gate
    }

    func read(_ binding: ProcessMetricBinding) -> ProcessMetricReadResult {
        gate?.pauseOnSecondRead()

        return lock.withLock {
            guard var results = queued[binding.token], !results.isEmpty else {
                return .unavailable(.readFailed(5))
            }

            let result            = results.removeFirst()
            queued[binding.token] = results
            return result
        }
    }
}
