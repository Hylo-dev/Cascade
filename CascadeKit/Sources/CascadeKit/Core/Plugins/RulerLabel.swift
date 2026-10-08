//
//  RulerLabel.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Synchronization

/// RulerLabel writes the label of a ruler slider tick, and the value VoiceOver reads for it.
/// With `duration` the value is minutes and the text is the stepper's own (`1h`, `1h 30m`,
/// `45m`), the units coming from the system's `Duration` formatting. With `clockTime` the value
/// is seconds since 1970 and the text is that instant's short time in the locale and the time
/// zone given (`18:00`, `6:00 PM`), which is the system's, not a literal.
nonisolated enum RulerLabel {

    static func text(
        value   : Double,
        labels  : PluginRulerLabels,
        locale  : Locale   = .current,
        timeZone: TimeZone = .current
    ) -> String {
        switch labels {
            case .duration:
                HoursMinutesCountdown.text(
                    remaining: value * 60,
                    locale   : locale
                )

            case .clockTime:
                Date(timeIntervalSince1970: value).formatted(
                    Date.FormatStyle(
                        date    : .omitted,
                        time    : .shortened,
                        locale  : locale,
                        timeZone: timeZone
                    )
                )
        }
    }
}

/// RulerLabelCache keeps the labels a ruler has written, so the drag, which redraws at the
/// display's rate, formats each hour once and not once a frame: building a `Duration` or a date
/// format style is the costliest thing a label does. A ruler shows at most a few hundred
/// distinct values, so the cache is cleared whole past 512 entries instead of being evicted.
/// It belongs to one ruler view, which lives as long as the page it is on, so a change of
/// locale or time zone is picked up the next time the page opens.
nonisolated final class RulerLabelCache: Sendable {

    private struct Key: Hashable {

        let value : Int
        let labels: PluginRulerLabels
    }

    private let entries = Mutex<[Key: String]>([:])

    func text(
        value : Double,
        labels: PluginRulerLabels
    ) -> String {
        let key = Key(value: Int(value.rounded()), labels: labels)

        if let cached = entries.withLock({ $0[key] }) {
            return cached
        }

        let text = RulerLabel.text(value: value, labels: labels)

        entries.withLock { entries in
            if entries.count >= 512 {
                entries.removeAll(keepingCapacity: true)
            }
            entries[key] = text
        }

        return text
    }
}
