//
//  ManualAudioHostTime.swift
//  CascadeKit
//

import Foundation
import Synchronization

/// ManualAudioHostTime is the clock and the scheduler of a service test, both moved by hand.
///
/// `schedule` only records the closure with the time it is due; nothing runs until the test
/// calls `advance`, which moves the clock and fires everything that came due, in due order, on
/// the calling thread (the service hops onto its queue itself). A closure that schedules another
/// one due immediately is fired in the same `advance`, which is how a zero-delay retry behaves.
final class ManualAudioHostTime: Sendable {

    private struct Pending {

        let due      : Duration
        let sequence : Int
        let work     : @Sendable () -> Void
    }

    private struct State {

        var now      : Duration  = .zero
        var sequence : Int       = 0
        var pending  : [Pending] = []
    }

    private let state = Mutex(State())

    var now: Duration {
        state.withLock { $0.now }
    }

    /// The delays still waiting, relative to now, in due order.
    var pendingDelays: [Duration] {
        state.withLock { state in
            state.pending
                .sorted { ($0.due, $0.sequence) < ($1.due, $1.sequence) }
                .map { $0.due - state.now }
        }
    }

    var pendingCount: Int {
        state.withLock { $0.pending.count }
    }

    var clock: @Sendable () -> Duration {
        { [self] in now }
    }

    var schedule: @Sendable (Duration, @escaping @Sendable () -> Void) -> Void {
        { [self] delay, work in enqueue(after: delay, work) }
    }

    private func enqueue(
        after delay : Duration,
        _ work      : @escaping @Sendable () -> Void
    ) {
        state.withLock { state in
            state.sequence += 1
            state.pending.append(Pending(due: state.now + delay, sequence: state.sequence, work: work))
        }
    }

    /// advance moves the clock forward by `interval` and fires what came due. `flush` runs after
    /// each closure so the service has applied it before the next one fires.
    func advance(
        by interval : Duration,
        flush       : () -> Void
    ) {
        let target = state.withLock { $0.now + interval }

        while let next = takeDue(upTo: target) {
            state.withLock { $0.now = max($0.now, next.due) }
            next.work()
            flush()
        }

        state.withLock { $0.now = target }
    }

    private func takeDue(upTo target: Duration) -> (due: Duration, work: @Sendable () -> Void)? {
        state.withLock { state in
            guard
                let index = state.pending.indices
                    .filter({ state.pending[$0].due <= target })
                    .min(by: { (state.pending[$0].due, state.pending[$0].sequence) < (state.pending[$1].due, state.pending[$1].sequence) })
            else { return nil }

            let pending = state.pending.remove(at: index)

            return (pending.due, pending.work)
        }
    }
}
