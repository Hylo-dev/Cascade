//
//  ChainReadSource.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Foundation
import Testing
@testable import CascadeRuntime

final class ChainReadSource: @unchecked Sendable {
    private let lock = NSLock()
    private var ticks: [UUID: [UInt64]]
    private var counts: [UUID: UInt64] = [:]
    private var captured: [ProcessMetricBinding] = []
    private let gatedToken: UUID?
    private let gate: ChainReadGate?

    init(
        _ ticks    : [UUID: [UInt64]],
        gatedToken: UUID? = nil,
        gate      : ChainReadGate? = nil
    ) {
        self.ticks = ticks
        self.gatedToken = gatedToken
        self.gate = gate
    }

    var bindings: [ProcessMetricBinding] { lock.withLock { captured } }

    func read(_ binding: ProcessMetricBinding) -> ProcessMetricReadResult {
        lock.withLock {
            captured.append(binding)
            guard var queued = ticks[binding.token], !queued.isEmpty else {
                return .unavailable(.readFailed(5))
            }
            let userTicks = queued.removeFirst()
            ticks[binding.token] = queued
            let count = (counts[binding.token] ?? 0) + 1
            counts[binding.token] = count
            if binding.token == gatedToken, count == 2 { gate?.pause() }
            return .sample(ProcessMetricObservation(
                binding       : binding,
                userTicks     : userTicks,
                systemTicks   : 0,
                footprintBytes: 4_096,
                window        : ProcessMetricWindow(
                    startTicks: count * 100 + 100,
                    endTicks  : count * 100 + 101
                ),
                timebase      : ProcessMetricTimebase(numer: 1, denom: 1)
            ))
        }
    }
}
