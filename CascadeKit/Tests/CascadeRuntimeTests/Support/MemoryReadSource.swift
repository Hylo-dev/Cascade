//
//  MemoryReadSource.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

final class MemoryReadSource: @unchecked Sendable {

    private let lock    = NSLock()
    private let binding: ProcessMetricBinding
    private var samples: [(UInt64?, UInt64?, UInt64?)]
    private var index   = 0

    init(
        binding    : ProcessMetricBinding,
        userTicks  : [UInt64?],
        systemTicks: [UInt64?],
        footprints : [UInt64?]
    ) {
        self.binding = binding
        samples      = Array(zip(zip(userTicks, systemTicks), footprints)).map { pair, footprint in
            (pair.0, pair.1, footprint)
        }
    }

    func read(_ requested: ProcessMetricBinding) -> ProcessMetricReadResult {
        lock.withLock {
            guard requested == binding, index < samples.count else {
                return .unavailable(.readFailed(5))
            }

            defer { index += 1 }
            let sample = samples[index]

            guard let user = sample.0, let system = sample.1, let footprint = sample.2 else {
                return .unavailable(.readFailed(5))
            }

            return .sample(ProcessMetricObservation(
                binding       : binding,
                userTicks     : user,
                systemTicks   : system,
                footprintBytes: footprint,
                window        : ProcessMetricWindow(
                    startTicks: UInt64(200 + index * 100),
                    endTicks  : UInt64(201 + index * 100)
                ),
                timebase      : ProcessMetricTimebase(numer: 1, denom: 1)
            ))
        }
    }
}
