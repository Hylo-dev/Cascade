//
//  HostTime.swift
//  CascadeKit
//

import Synchronization

/// HostTime is the executor's clock and its delayed work, both driven by the test.
final class HostTime: Sendable {

    private let instant = Mutex(Duration.zero)
    private let pending = Mutex<[(delay: Duration, work: @Sendable () -> Void)]>([])

    var now: Duration {
        instant.withLock { $0 }
    }

    var delays: [Duration] {
        pending.withLock { $0.map(\.delay) }
    }

    func set(_ seconds: Int) {
        instant.withLock { $0 = .seconds(seconds) }
    }

    func schedule(
        _ delay: Duration,
        _ work : @escaping @Sendable () -> Void
    ) {
        pending.withLock { $0.append((delay, work)) }
    }

    /// runDelayed performs every delayed task, as if its time had come.
    func runDelayed() {
        let due = pending.withLock { pending in
            defer { pending.removeAll() }

            return pending.map(\.work)
        }
        due.forEach { $0() }
    }
}
