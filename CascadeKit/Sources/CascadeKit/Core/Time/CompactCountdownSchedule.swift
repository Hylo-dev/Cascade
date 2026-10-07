//
//  CompactCountdownSchedule.swift
//  CascadeKit
//

import Foundation
import SwiftUI

/// CompactCountdownSchedule is the `TimelineSchedule` that keeps a compact countdown current
/// at the least possible cost: its entries are the date a view appears and then only the
/// instants at which the text changes, ending with the one just past `end`. A countdown with
/// hours left is redrawn once an hour, one with minutes left once a minute, and only the last
/// five minutes tick every second.
///
/// An `end` that is already past yields the start date alone, so a view that appears late
/// draws `0:00` once and then asks for nothing. The update mode is ignored on purpose: the
/// boundaries are already sparse, and the text must stay right in low-frequency mode too.
nonisolated struct CompactCountdownSchedule: TimelineSchedule {

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

            pending = CompactCountdown.nextChange(
                after: current,
                end  : end
            )

            return current
        }
    }
}
