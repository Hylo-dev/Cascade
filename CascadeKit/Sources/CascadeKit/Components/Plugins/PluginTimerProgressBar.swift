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
/// than once a second, so a day's bar redraws every three minutes and a year's twice a day; it
/// stops at the end, where a finished bar has nothing left to draw. The system bar also turns
/// grey in a window that is never key, which the notch's panel never is. This one fills with the
/// node's own foreground style, white unless the node names one, over a dim track of the same
/// colour, and reads to VoiceOver as a progress indicator.
struct PluginTimerProgressBar: View {

    static let height = 5.0

    let start   : Date
    let end     : Date
    let isStyled: Bool

    var body: some View {
        if isStyled {
            bar
        } else {
            bar
                .foregroundStyle(.white)
        }
    }

    private var bar: some View {
        TimelineView(Schedule(start: start, end: end)) { context in
            let fraction = Self.fraction(at: context.date, from: start, to: end)

            Capsule()
                .fill(.foreground.opacity(0.22))
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(.foreground)
                            .frame(width: proxy.size.width * fraction)
                    }
                }
                .frame(height: Self.height)
                .accessibilityRepresentation {
                    ProgressView(value: fraction)
                }
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
    /// the last one at or before the moment the view asks, through the end. Asked after the end,
    /// it gives the end alone, so the bar draws full once and the timeline stops.
    nonisolated struct Schedule: TimelineSchedule {

        let start: Date
        let end  : Date

        func entries(
            from date: Date,
            mode     : TimelineScheduleMode
        ) -> StrideThrough<Date> {
            let step  = PluginTimerProgressBar.step(from: start, to: end)
            let first = start.addingTimeInterval((date.timeIntervalSince(start) / step).rounded(.down) * step)

            return stride(from: min(first, end), through: end, by: step)
        }
    }
}
