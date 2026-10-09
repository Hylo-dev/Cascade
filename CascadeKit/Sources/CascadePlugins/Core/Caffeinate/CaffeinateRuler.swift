//
//  CaffeinateRuler.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// CaffeinateRuler decides what the options page's ruler measures: its value, its range, the
/// words of its labels and the action it sends. It is a pure function of the snapshot, of
/// "now" and of the calendar, so the page, the widget's status line and the tests agree on one
/// answer, and none of it holds state.
///
/// The ruler has two scales. A duration is minutes, 15 to 1440 in steps of 15. An end time is
/// an instant in seconds since 1970 on the quarter hours of the clock, from the first quarter
/// hour at least 15 minutes ahead to the last one within a day. The range is built from the
/// moment the page is published, so it is as stale as the page is: the native owner rejects
/// an instant that has meanwhile gone too close, and the ruler returns to its published value
/// by itself (`PluginNodeStore.confirmationTimeout`).
///
/// The value is what the control stands for now. While off, it is the next session's target. While
/// a session runs, a duration is the time left rounded up to the next quarter hour, since the
/// ruler cannot show less than a tick and an end that is a little away should not read as shorter
/// than it is; an end time is the session's end. A value the range would not contain, such as an
/// end that is closer than 15 minutes, widens the range to hold it, because a document whose
/// slider is out of its range is rejected whole.
enum CaffeinateRuler {

    /// labelEvery is the ticks between two labels: a tick is a quarter hour, so an hour.
    static let labelEvery = 4

    struct Scale: Equatable {

        let value     : Double
        let lowerBound: Double
        let upperBound: Double
        let step      : Double
        let labels    : PluginRulerLabels
        let action    : String
    }

    private static let durationStep = Double(CaffeinateTarget.step)
    private static let quarterHour  = Double(CaffeinateTarget.step * 60)

    /// scale answers the ruler to draw for the kind of target the page shows, or nil for an
    /// indefinite session, which has nothing to measure.
    static func scale(
        for state: PluginCaffeinateState,
        now      : Date,
        calendar : Calendar
    ) -> Scale? {
        switch state.shownKind {
            case .indefinite:
                nil

            case .duration:
                duration(state, now: now)

            case .until:
                until(state, now: now, calendar: calendar)
        }
    }

    /// nextEnd is when the next session would end if it started now, for an end time: the
    /// instant the native owner resolves, on the nearest quarter hour. Nil for other targets.
    static func nextEnd(
        of state: PluginCaffeinateState,
        now     : Date,
        calendar: Calendar
    ) -> Date? {
        guard case .until = state.nextTarget,
              let end = state.nextTarget.end(startingAt: now, calendar: calendar)
        else { return nil }

        return Date(timeIntervalSince1970: nearestQuarter(end.timeIntervalSince1970))
    }

    private static func duration(
        _ state: PluginCaffeinateState,
        now    : Date
    ) -> Scale {
        let shortest = durationStep
        let longest  = Double(CaffeinateTarget.maximumMinutes)
        let value: Double

        if state.isActive, let endsAt = state.endsAt {
            let minutesLeft = max(0, endsAt.timeIntervalSince(now)) / 60
            value           = (minutesLeft / durationStep).rounded(.up) * durationStep
        } else if case .duration(let minutes) = state.nextTarget {
            value = Double(minutes)
        } else {
            value = shortest
        }

        return Scale(
            value     : min(max(value, shortest), longest),
            lowerBound: shortest,
            upperBound: longest,
            step      : durationStep,
            labels    : .duration,
            action    : CaffeinateStyle.Action.durationSet
        )
    }

    private static func until(
        _ state : PluginCaffeinateState,
        now     : Date,
        calendar: Calendar
    ) -> Scale {
        let seconds = now.timeIntervalSince1970
        let lowest  = ((seconds + CaffeinateTarget.minimumLead) / quarterHour).rounded(.up) * quarterHour
        let highest = ((seconds + CaffeinateTarget.maximumLength) / quarterHour).rounded(.down) * quarterHour
        let end     = state.isActive
            ? state.endsAt?.timeIntervalSince1970
            : nextEnd(of: state, now: now, calendar: calendar)?.timeIntervalSince1970
        let value   = nearestQuarter(end ?? lowest)

        return Scale(
            value     : value,
            lowerBound: min(lowest, value),
            upperBound: max(highest, value),
            step      : quarterHour,
            labels    : .clockTime,
            action    : CaffeinateStyle.Action.untilSet
        )
    }

    private static func nearestQuarter(_ seconds: Double) -> Double {
        (seconds / quarterHour).rounded() * quarterHour
    }
}
