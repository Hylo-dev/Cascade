//
//  TimerText.swift
//  CascadeKit
//

import Foundation

/// TimerText writes a timer node the way SwiftUI's own `Text(timerInterval:)` does: the whole
/// seconds elapsed, or left when counting down, as `m:ss` and, from an hour up, `h:mm:ss`. It is
/// a pure function of the date, so the label that shows it can be driven by any schedule, and
/// the kernel can roll its digits instead of letting SwiftUI redraw the whole text.
///
/// The count is clamped to the interval: before `start` it is the first value, after `end` the
/// last, never negative and never past the length. It is `nonisolated`, as the schedule that
/// drives it is free to run wherever SwiftUI asks.
nonisolated enum TimerText {

    static func text(
        start     : Date,
        end       : Date,
        countsDown: Bool,
        at date   : Date,
        locale    : Locale = .current
    ) -> String {
        let length  = max(0, end.timeIntervalSince(start)).rounded(.down)
        let elapsed = min(max(0, date.timeIntervalSince(start)).rounded(.down), length)
        let seconds = countsDown ? length - elapsed : elapsed

        if seconds >= 3_600 {
            return Duration.seconds(seconds).formatted(
                .time(pattern: .hourMinuteSecond).locale(locale)
            )
        }

        return Duration.seconds(seconds).formatted(
            .time(pattern: .minuteSecond).locale(locale)
        )
    }
}
