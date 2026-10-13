//
//  ManualAudioClock.swift
//  CascadeTests
//

import Synchronization

/// ManualAudioClock is the time the service reads in a test: it moves only when the test says.
final class ManualAudioClock: Sendable {

    private let now = Mutex(Duration.zero)

    func read() -> Duration {
        now.withLock { $0 }
    }

    func advance(by amount: Duration) {
        now.withLock { $0 += amount }
    }
}
