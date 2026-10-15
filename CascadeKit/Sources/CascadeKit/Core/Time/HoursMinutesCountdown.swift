//
//  HoursMinutesCountdown.swift
//  CascadeKit
//

import Foundation

/// HoursMinutesCountdown writes the time left as a stepper shows a duration: hours and minutes,
/// the minutes rounded up (`2h`, `1h 5m`, `45m`, `1m`), `0m` once the end is reached. Rounding up
/// is what a stepper whose owner steps from the time left rounded up needs: one minute and a few
/// seconds left reads `2m`, never less than is left, and every step of fifteen minutes changes
/// the text. The units come from the system's `Duration` formatting, not from literals.
///
/// As with `CompactCountdown`, the text is a pure function of `remaining` and `nextChange` is its
/// exact inverse, so a view redraws once a minute and never in between. Both are `nonisolated`:
/// CascadeKit defaults to the main actor, and the schedule's iterator runs wherever SwiftUI asks.
nonisolated enum HoursMinutesCountdown {

    /// text is the hours-and-minutes form of `remaining` seconds, rounded up to whole minutes.
    static func text(
        remaining: TimeInterval,
        locale   : Locale = .current
    ) -> String {
        let minutes = remaining > 0 ? (remaining / 60).rounded(.up) : 0

        return Duration.seconds(minutes * 60).formatted(
            .units(allowed: [.hours, .minutes], width: .narrow).locale(locale)
        )
    }

    /// nextChange is the first instant after `now` at which the text for `end` differs from the
    /// text at `now`, nudged just past the boundary, or nil once `end` has been reached.
    ///
    /// The text shows `k` minutes for a time left in `((k - 1) · 60, k · 60]`, so it flips the
    /// moment the time left reaches the largest whole minute strictly below it. The boundary is
    /// below the time left and the nudge positive, so the answer is always after `now`. The nudge
    /// keeps a `Date` rounding from landing the entry a hair before the flip, where it would draw
    /// the old value; at the last minute the boundary is zero and the entry lands just past `end`.
    static func nextChange(
        after now: Date,
        end      : Date
    ) -> Date? {
        let remaining = end.timeIntervalSince(now)

        guard remaining > 0, remaining.isFinite else {
            return nil
        }

        let boundary = ((remaining / 60).rounded(.up) - 1) * 60

        return end.addingTimeInterval(CompactCountdown.nudge - boundary)
    }
}
