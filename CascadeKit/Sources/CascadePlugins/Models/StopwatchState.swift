//
//  StopwatchState.swift
//  CascadeKit
//

import Foundation

/// StopwatchState is all the stopwatch widget remembers: nothing counted, counting since a moment
/// with what it had counted before it, or held with what it counted. Running keeps the two apart
/// rather than a single start, so a pause and a resume never lose a fraction of a second, and the
/// kernel draws the count from `since - before`, as if it had never paused. The transitions are
/// pure, like the timer's, and one that does not apply returns the state unchanged.
enum StopwatchState: Equatable, Sendable {

    case idle
    case running(since: Date, before: TimeInterval)
    case paused(elapsed: TimeInterval)

    /// starting counts from nothing, or resumes from what was counted; a running stopwatch stays
    /// as it is.
    func starting(at now: Date) -> StopwatchState {
        switch self {
            case .idle:
                .running(since: now, before: 0)

            case .paused(let elapsed):
                .running(since: now, before: elapsed)

            case .running:
                self
        }
    }

    /// pausing holds a running stopwatch with all it counted.
    func pausing(at now: Date) -> StopwatchState {
        guard case .running(let since, let before) = self else { return self }

        return .paused(elapsed: before + max(0, now.timeIntervalSince(since)))
    }

    func resetting() -> StopwatchState {
        .idle
    }
}
