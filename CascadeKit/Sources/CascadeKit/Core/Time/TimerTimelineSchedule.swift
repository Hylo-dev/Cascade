//
//  TimerTimelineSchedule.swift
//  CascadeKit
//

import Foundation
import SwiftUI

/// TimerTimelineSchedule is the whole-second schedule of a timer node: the date a view appears,
/// then every second counted from `start`, ending with the tick at `end`. It is what
/// `.periodic(from: start, by: 1)` would be, except that it stops. A timer left on screen after
/// it ran out would otherwise wake the CPU every second for as long as the notch lives, to draw
/// the same text; here it draws the last value once and asks for nothing more.
///
/// A view that appears late starts at its own date, and one that appears before `start` ticks
/// first at `start`. The update mode is ignored on purpose: the label shows seconds, and low
/// frequency mode must not freeze it.
nonisolated struct TimerTimelineSchedule: TimelineSchedule {

    let start: Date
    let end  : Date

    func entries(
        from startDate: Date,
        mode          : TimelineScheduleMode
    ) -> Entries {
        Entries(
            start  : start,
            end    : end,
            pending: startDate
        )
    }

    /// Entries walks the ticks lazily, holding three dates and nothing else.
    struct Entries: Sequence, IteratorProtocol {

        let start  : Date
        let end    : Date
        var pending: Date?

        mutating func next() -> Date? {
            guard let current = pending else {
                return nil
            }

            pending = tick(after: current)

            return current
        }

        /// tick is the first whole second counted from `start` that is strictly after `date`,
        /// or nil past `end`.
        private func tick(after date: Date) -> Date? {
            let elapsed = date.timeIntervalSince(start)
            let next    = elapsed < 0 ? start : start.addingTimeInterval(elapsed.rounded(.down) + 1)

            return next <= end ? next : nil
        }
    }
}
