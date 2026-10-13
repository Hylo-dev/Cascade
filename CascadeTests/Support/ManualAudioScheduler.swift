//
//  ManualAudioScheduler.swift
//  CascadeTests
//

import Foundation
import Synchronization

/// ManualAudioScheduler keeps the service's one-shot callbacks until the test fires them. With
/// ManualAudioClock, the time the service reads, a test walks through the 3-second deadline and
/// the restart backoff without waiting for either.
final class ManualAudioScheduler: Sendable {

    private struct Entry {

        let delay: Duration
        let work : @Sendable () -> Void
        var hasFired = false
    }

    private let entries = Mutex<[Entry]>([])

    /// delays lists every delay the service asked for, in order.
    var delays: [Duration] {
        entries.withLock { $0.map(\.delay) }
    }

    var unfiredCount: Int {
        entries.withLock { $0.filter { !$0.hasFired }.count }
    }

    func schedule(
        _ delay: Duration,
        _ work : @escaping @Sendable () -> Void
    ) {
        entries.withLock { $0.append(Entry(delay: delay, work: work)) }
    }

    /// fireAll runs, in order, every callback that had not run yet when it was called; those the
    /// run itself schedules wait for the next call.
    func fireAll() {
        let due = entries.withLock { entries -> [@Sendable () -> Void] in
            var due: [@Sendable () -> Void] = []
            for index in entries.indices where !entries[index].hasFired {
                entries[index].hasFired = true
                due.append(entries[index].work)
            }

            return due
        }

        due.forEach { $0() }
    }
}
