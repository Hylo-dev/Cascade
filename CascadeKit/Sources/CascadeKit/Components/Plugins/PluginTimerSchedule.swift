import Foundation
import SwiftUI

/// PluginTimerSchedule yields second boundaries lazily, including the final value once.
/// An expired timer has no future entries, so a retained final label costs no wakeups.
struct PluginTimerSchedule: TimelineSchedule {

    let start: Date
    let end  : Date

    func entries(from date: Date, mode: Mode) -> Entries {
        let boundary = start.addingTimeInterval(ceil(max(0, date.timeIntervalSince(start))))
        return Entries(date: date <= end ? min(boundary, end) : nil, end: end)
    }

    struct Entries: Sequence, IteratorProtocol {

        var date: Date?
        let end : Date

        mutating func next() -> Date? {
            guard let current = date else { return nil }
            date = current < end ? Swift.min(current.addingTimeInterval(1), end) : nil
            return current
        }
    }
}
