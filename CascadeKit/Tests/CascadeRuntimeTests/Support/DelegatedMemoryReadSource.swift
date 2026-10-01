//
//  DelegatedMemoryReadSource.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

final class DelegatedMemoryReadSource: @unchecked Sendable {

    private let lock       = NSLock()
    private var samples   : [UUID: [(UInt64, UInt64)]]
    private var counts    : [UUID: UInt64] = [:]
    private let gatedToken: UUID?
    private let gate      : MemoryReadGate?

    init(
        samples   : [UUID: [(UInt64, UInt64)]],
        gatedToken: UUID? = nil,
        gate      : MemoryReadGate? = nil
    ) {
        self.samples    = samples
        self.gatedToken = gatedToken
        self.gate       = gate
    }

    func read(_ binding: ProcessMetricBinding) -> ProcessMetricReadResult {
        let count = lock.withLock { () -> UInt64 in
            let count = counts[binding.token, default: 0]
            counts[binding.token] = count + 1

            return count
        }

        if binding.token == gatedToken, count == 1 { gate?.pause() }

        return lock.withLock {
            guard var values = samples[binding.token], !values.isEmpty else {
                return .unavailable(.readFailed(5))
            }

            let value = values.removeFirst()
            samples[binding.token] = values

            return .sample(ProcessMetricObservation(
                binding       : binding,
                userTicks     : value.0,
                systemTicks   : 0,
                footprintBytes: value.1,
                window        : ProcessMetricWindow(
                    startTicks: 200 + count * 100,
                    endTicks  : 201 + count * 100
                ),
                timebase: ProcessMetricTimebase(numer: 1, denom: 1)
            ))
        }
    }
}
