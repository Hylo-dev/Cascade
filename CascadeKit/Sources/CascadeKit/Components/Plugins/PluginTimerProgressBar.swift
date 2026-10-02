//
//  PluginTimerProgressBar.swift
//  CascadeKit
//

import SwiftUI

/// PluginTimerProgressBar draws a `timerProgress` node: a thin capsule that fills from the
/// interval's start to its end, drawn and kept current by the kernel so the plugin never runs to
/// move it.
///
/// It is not SwiftUI's `ProgressView(timerInterval:)`, which redraws every frame while it is on
/// screen: four of them, the progress widget's tall tile, cost 13 to 19% of a core in the
/// notch's panel, against 0.01% for this bar. Its timeline steps every five hundredth of the
/// interval, which moves a 110-point bar by a fifth of a point at a time, and never more often
/// than once a second, so a day's bar redraws about every three minutes and a year's about every
/// seventeen and a half hours; it stops once it has drawn the end, where a finished bar has
/// nothing left to draw. Each step draws the kernel's `PluginProgressBar` at the fraction
/// reached, the bar a linear progress draws too.
struct PluginTimerProgressBar: View {

    let start: Date
    let end  : Date

    var body: some View {
        TimelineView(Schedule(start: start, end: end)) { context in
            PluginProgressBar(fraction: Self.fraction(at: context.date, from: start, to: end))
        }
    }

    /// step is how long the bar waits between redraws: a five hundredth of the interval, at least
    /// a second.
    nonisolated static func step(
        from start: Date,
        to end    : Date
    ) -> TimeInterval {
        max(1, end.timeIntervalSince(start) / 500)
    }

    /// fraction is how much of the interval has gone at `date`, from 0 before it to 1 after it; an
    /// empty interval is full from its only moment on.
    nonisolated static func fraction(
        at date   : Date,
        from start: Date,
        to end    : Date
    ) -> Double {
        let span = end.timeIntervalSince(start)
        guard span > 0 else { return date >= end ? 1 : 0 }

        return min(max(date.timeIntervalSince(start) / span, 0), 1)
    }

    /// Schedule is the bar's timeline: the steps of a grid laid from the interval's start, from
    /// the last one at or before the moment the view asks, or from the start when it lies ahead,
    /// to two steps past the end.
    ///
    /// SwiftUI draws a first entry dated later at once and every later entry when its time comes,
    /// but never the last entry of a finite timeline. Two steps past the end make the last entry
    /// drawn the first at or after the end, so the bar is drawn full however its end falls on the
    /// grid; stopping at the end would leave an 8-second bar at seven eighths for good. Starting a
    /// bar that lies ahead at its start draws it once, empty, until it starts, where the grid
    /// would redraw it every step to no effect. Asked after the end, the schedule gives the end
    /// alone, which SwiftUI draws, so the bar is drawn full once and the timeline stops.
    nonisolated struct Schedule: TimelineSchedule {

        let start: Date
        let end  : Date

        func entries(
            from date: Date,
            mode     : TimelineScheduleMode
        ) -> StrideThrough<Date> {
            let step = PluginTimerProgressBar.step(from: start, to: end)
            guard date < end else { return stride(from: end, through: end, by: step) }

            let first = date < start
                ? start
                : start.addingTimeInterval((date.timeIntervalSince(start) / step).rounded(.down) * step)

            return stride(from: first, through: end.addingTimeInterval(2 * step), by: step)
        }
    }
}
