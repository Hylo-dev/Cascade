//
//  CompactCountdown.swift
//  CascadeKit
//

import Foundation

/// CompactCountdown writes the time left the way the Dynamic Island does: whole hours from
/// an hour up (`2h`), whole minutes from five minutes up (`24m`), `m:ss` below that (`4:59`).
/// Every unit is floored, never rounded, so a countdown never shows less time than is left
/// and never jumps a unit early.
///
/// The text is a pure function of `remaining`, and `nextChange(after:end:)` is its exact
/// inverse: the first instant at which that function returns something else. A view that
/// redraws only at those instants costs the CPU one wake per visible change, which is the whole
/// point: a countdown of eight hours wakes eight times, not 28 800.
///
/// Both are `nonisolated`: CascadeKit defaults to the main actor, and the schedule's iterator
/// is free to run wherever SwiftUI asks it to.
nonisolated enum CompactCountdown {

    /// nudge moves a change instant just past its boundary. The text flips when the time left
    /// drops *below* a boundary, so an entry exactly on it would still read the old text, and
    /// the redraw would show a stale value until the next one. A millisecond is far above the
    /// precision of a `Date` (about 0.2 µs today) and far below anything the eye can see.
    static let nudge: TimeInterval = 0.001

    /// text is the compact form of `remaining` seconds. Anything at or below zero is `0:00`.
    static func text(
        remaining: TimeInterval,
        locale   : Locale = .current
    ) -> String {
        guard remaining > 0 else {
            return Self.minutesAndSeconds(0, locale: locale)
        }

        if remaining >= 3_600 {
            let hours = (remaining / 3_600).rounded(.down)

            return Duration.seconds(hours * 3_600).formatted(
                .units(allowed: [.hours], width: .narrow).locale(locale)
            )
        }

        if remaining >= 300 {
            let minutes = (remaining / 60).rounded(.down)

            return Duration.seconds(minutes * 60).formatted(
                .units(allowed: [.minutes], width: .narrow).locale(locale)
            )
        }

        return Self.minutesAndSeconds(remaining.rounded(.down), locale: locale)
    }

    /// nextChange is the first instant after `now` at which the text for `end` differs from the
    /// text at `now`, nudged just past the boundary, or nil once `end` has been reached.
    ///
    /// The text changes whenever the time left drops below a boundary: a multiple of an hour,
    /// a multiple of a minute from five up to fifty-nine, or a whole second under five
    /// minutes. The answer is the largest boundary strictly below the time left, which is
    /// computed with a `ceil`, so there is no loop and no allocation.
    static func nextChange(
        after now: Date,
        end      : Date
    ) -> Date? {
        let remaining = end.timeIntervalSince(now)

        guard remaining > 0, remaining.isFinite else {
            return nil
        }

        let boundary: TimeInterval

        if remaining > 3_600 {
            boundary = (remaining / 3_600).rounded(.up) * 3_600 - 3_600
        } else if remaining > 300 {
            boundary = max(300, (remaining / 60).rounded(.up) * 60 - 60)
        } else {
            boundary = remaining.rounded(.up) - 1
        }

        return end.addingTimeInterval(nudge - boundary)
    }

    /// minutesAndSeconds formats whole seconds as `m:ss` in the given locale.
    private static func minutesAndSeconds(
        _ seconds: TimeInterval,
        locale   : Locale
    ) -> String {
        Duration.seconds(seconds).formatted(
            .time(pattern: .minuteSecond).locale(locale)
        )
    }
}
