//
//  HostEvents.swift
//  CascadeTests
//

import CascadePluginEngine
import Synchronization

/// HostEvents records the availability an executor reports and lets a test wait for it.
final class HostEvents: Sendable {

    private let recorded = Mutex<[PluginExecutorEvent]>([])

    func record(_ event: PluginExecutorEvent) {
        recorded.withLock { $0.append(event) }
    }

    /// wait returns once `event` was reported `count` times, or false after `limit`.
    func wait(
        for event: PluginExecutorEvent,
        count    : Int,
        within limit: Duration = .seconds(10)
    ) async throws -> Bool {
        let deadline = ContinuousClock.now.advanced(by: limit)
        while recorded.withLock({ $0.count { $0 == event } }) < count, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        return recorded.withLock { $0.count { $0 == event } } >= count
    }
}
