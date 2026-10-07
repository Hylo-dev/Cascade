//
//  HoursMinutesCountdownSchedule.swift
//  CascadeKit
//

import Foundation
import SwiftUI

/// HoursMinutesCountdownSchedule is the `TimelineSchedule` of an hours-and-minutes countdown: the
/// date a view appears, then only the instants at which the text changes, one a minute, ending
/// with the one just past `end`. An `end` already past yields the start date alone, so a view
/// that appears late draws `0m` once and asks for nothing more. The update mode is ignored on
/// purpose: the entries are already a minute apart.
nonisolated struct HoursMinutesCountdownSchedule: TimelineSchedule {

    let end: Date

    func entries(
        from startDate: Date,
        mode          : TimelineScheduleMode
    ) -> Entries {
        Entries(
            end    : end,
            pending: startDate
        )
    }

    /// Entries walks the change instants lazily, holding two dates and nothing else.
    struct Entries: Sequence, IteratorProtocol {

        let end    : Date
        var pending: Date?

        mutating func next() -> Date? {
            guard let current = pending else {
                return nil
            }

            pending = HoursMinutesCountdown.nextChange(
                after: current,
                end  : end
            )

            return current
        }
    }
}
