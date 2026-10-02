//
//  TimerState.swift
//  CascadeKit
//

import Foundation

/// TimerState is all the timer widget remembers: nothing running, with the length set so far, a
/// countdown to its end, or a countdown held with what it had left. The last two keep the total
/// the timer was set to, which is what its bar fills against. The transitions are pure and take
/// the moment they happen at, so the plugin reads its clock once per event and the tests stand
/// anywhere in time; a transition that does not apply returns the state unchanged, which is how
/// the plugin knows to publish nothing.
///
/// The total never passes 99 minutes: an addition is cut to what that leaves. A running timer's
/// end moves by as much as its total does, so its bar keeps the start it had.
enum TimerState: Equatable, Sendable {

    case idle(duration: TimeInterval)
    case running(end: Date, duration: TimeInterval)
    case paused(remaining: TimeInterval, duration: TimeInterval)

    static let longestDuration: TimeInterval = 99 * 60

    /// adding sets or extends the timer by `seconds`, up to the cap, and never starts it; only
    /// `starting` does. What it adds does not depend on the moment, which it takes as every
    /// transition does.
    func adding(
        _ seconds: TimeInterval,
        at now   : Date
    ) -> TimerState {
        switch self {
            case .idle(let duration):
                return .idle(duration: min(duration + seconds, Self.longestDuration))

            case .running(let end, let duration):
                let added = min(seconds, max(0, Self.longestDuration - duration))

                return .running(end: end.addingTimeInterval(added), duration: duration + added)

            case .paused(let remaining, let duration):
                let added = min(seconds, max(0, Self.longestDuration - duration))

                return .paused(remaining: remaining + added, duration: duration + added)
        }
    }

    /// starting runs an idle timer for its length, or resumes a paused one for what it had left;
    /// a timer with nothing set or nothing left, or already running, stays as it is.
    func starting(at now: Date) -> TimerState {
        switch self {
            case .idle(let duration) where duration > 0:
                .running(end: now.addingTimeInterval(duration), duration: duration)

            case .paused(let remaining, let duration) where remaining > 0:
                .running(end: now.addingTimeInterval(remaining), duration: duration)

            default:
                self
        }
    }

    /// pausing holds a running timer with what it has left, nothing once its end has passed.
    func pausing(at now: Date) -> TimerState {
        guard case .running(let end, let duration) = self else { return self }

        return .paused(remaining: max(0, end.timeIntervalSince(now)), duration: duration)
    }

    func resetting() -> TimerState {
        .idle(duration: 0)
    }

    /// isFinished is true once a running timer's end has come.
    func isFinished(at now: Date) -> Bool {
        guard case .running(let end, _) = self else { return false }

        return now >= end
    }
}
