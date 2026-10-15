//
//  RulerLabel.swift
//  CascadeKit
//

import CascadeContracts
import Combine
import Foundation

/// RulerLabel writes the label of a ruler slider tick, and the value VoiceOver reads for it.
/// With `duration` the value is minutes and the text is the stepper's own (`1h`, `1h 30m`,
/// `45m`), the units coming from the system's `Duration` formatting. With `clockTime` the value
/// is seconds since 1970 and the text is that instant's short time in the locale and the time
/// zone given (`18:00`, `6:00 PM`), which is the system's, not a literal.
///
/// `spoken` is the same value for VoiceOver: a tick's label is narrow because it is small, but
/// "1h 30m" is read letter by letter, so a duration is spoken in full (`1 hour, 30 minutes`);
/// an instant is already a time and is spoken as written.
nonisolated enum RulerLabel {

    static func spoken(
        value   : Double,
        labels  : PluginRulerLabels,
        locale  : Locale   = .current,
        timeZone: TimeZone = .current
    ) -> String {
        switch labels {
            case .duration:
                Duration.seconds(value * 60).formatted(
                    .units(allowed: [.hours, .minutes], width: .wide).locale(locale)
                )

            case .clockTime:
                text(
                    value   : value,
                    labels  : labels,
                    locale  : locale,
                    timeZone: timeZone
                )
        }
    }

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
///
/// It belongs to one ruler view, which owns it as a `@StateObject`: SwiftUI builds it once per
/// view identity, where a plain `@State` would allocate a throwaway one at every init of the
/// view's struct. It has no `@Published` property, so reading it never invalidates a view. It is
/// touched only on the main actor, where the ruler's body and its canvas run, and so it takes no
/// lock. A change of locale or time zone is picked up the next time the page opens.
final class RulerLabelCache: ObservableObject {

    private struct Key: Hashable {

        let value : Int
        let labels: PluginRulerLabels
        let spoken: Bool
    }

    private var entries = [Key: String]()

    /// text is the label drawn on a tick: narrow, as the stepper's.
    func text(
        value : Double,
        labels: PluginRulerLabels
    ) -> String {
        cached(Key(value: Int(value.rounded()), labels: labels, spoken: false)) {
            RulerLabel.text(value: value, labels: labels)
        }
    }

    /// spoken is what VoiceOver reads for a value: the full form of the label.
    func spoken(
        value : Double,
        labels: PluginRulerLabels
    ) -> String {
        cached(Key(value: Int(value.rounded()), labels: labels, spoken: true)) {
            RulerLabel.spoken(value: value, labels: labels)
        }
    }

    private func cached(
        _ key : Key,
        make  : () -> String
    ) -> String {
        if let cached = entries[key] {
            return cached
        }

        if entries.count >= 512 {
            entries.removeAll(keepingCapacity: true)
        }

        let text = make()
        entries[key] = text

        return text
    }
}
