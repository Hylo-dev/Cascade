//
//  SystemRuntimeClock.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// SystemRuntimeClock is the production clock for runtime deadline decisions.
struct SystemRuntimeClock: RuntimeClock {
    func now() -> RuntimeInstant {
        RuntimeInstant(
            wall     : Date(),
            monotonic: .seconds(ProcessInfo.processInfo.systemUptime)
        )
    }
}
