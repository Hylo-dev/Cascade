//
//  WakeReadSource.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing
@testable import CascadeRuntime

/// WakeReadSource pauses only its third real read, which would otherwise
/// deliver a complete positive-credit interval across the host wake.
final class WakeReadSource: @unchecked Sendable {

    private let lock                 = NSLock()
    private let binding             : ProcessMetricBinding
    private let gate                 = WakeResetGate()
    private var count                = 0
    private var shouldPauseThirdRead = false

    var readCount: Int { lock.withLock { count } }

    init(binding: ProcessMetricBinding) {
        self.binding = binding
    }

    func pauseThirdRead() {
        lock.withLock { shouldPauseThirdRead = true }
    }

    func waitForArrival() -> Bool { gate.waitForArrival() }

    func release() { gate.release() }

    func read(_ observed: ProcessMetricBinding) -> ProcessMetricReadResult {
        let (ordinal, pause) = lock.withLock { () -> (Int, Bool) in
            count += 1
            return (count, count == 3 && shouldPauseThirdRead)
        }

        if pause { gate.pause() }
        guard observed == binding else { return .unavailable(.identityMismatch) }

        let ticks: UInt64 = ordinal == 1 ? 0 : 150_000_000
        let start = UInt64(ordinal) * 100

        return .sample(ProcessMetricObservation(
            binding       : observed,
            userTicks     : ticks,
            systemTicks   : 0,
            footprintBytes: 4_096,
            window        : ProcessMetricWindow(startTicks: start, endTicks: start + 1),
            timebase      : ProcessMetricTimebase(numer: 1, denom: 1)
        ))
    }
}
