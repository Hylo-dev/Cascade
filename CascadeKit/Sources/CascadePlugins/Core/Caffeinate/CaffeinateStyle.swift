//
//  CaffeinateStyle.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// CaffeinateStyle gathers what the faces share: the identities of the controls, the
/// actions they send, the palette, the words and the few formats. The faces are pure functions
/// of the snapshot and of "now", so none of this holds state.
///
/// Every control has one explicit identity per placement, whatever the session does, so a
/// publication updates a control in place instead of replacing it, and the native owner maps
/// the action by name, never by the node's identity.
enum CaffeinateStyle {

    /// Node holds the explicit identities. Each placement of the power control has its own,
    /// because identities are unique within a document and the widget's three faces and its
    /// options page each draw one. The 2x2 face's opener is `options`, the 2x1 face's
    /// `options.large`, for the same reason.
    ///
    /// The options page's selector has one button for each way a session can end, and the
    /// ruler keeps one identity whatever it measures, so choosing For or Until updates it in
    /// place, with its range, instead of replacing it.
    enum Node {

        static let powerMedium  = "power.medium"
        static let powerLarge   = "power.large"
        static let powerSmall   = "power.small"
        static let powerOptions = "power.options"
        static let display      = "display"
        static let opener       = "options"
        static let openerLarge  = "options.large"
        static let page         = "options.page"
        static let ruler        = "ruler"

        /// mode is the selector's segment for a kind of target.
        static func mode(_ kind: CaffeinateTargetKind) -> String {
            "mode.\(kind.rawValue)"
        }
    }

    enum Action {

        static let start        = "caffeinate.start"
        static let stop         = "caffeinate.stop"
        static let display      = "caffeinate.display"
        static let options      = "caffeinate.options"
        static let durationSet  = "caffeinate.duration.set"
        static let untilSet     = "caffeinate.until.set"

        /// mode is the one action a selector segment sends: it is a button, and the native
        /// owner answers by name.
        static func mode(_ kind: CaffeinateTargetKind) -> String {
            "caffeinate.mode.\(kind.rawValue)"
        }

        /// power is the one action a power control sends in a given state: it is a toggle whose
        /// value says "on", and the owner answers by name.
        static func power(isActive: Bool) -> String {
            isActive ? stop : start
        }
    }

    enum Palette {

        static let amber     = PluginColor(red: 1, green: 0.77, blue: 0.33)
        static let ink       = PluginColor(red: 0.15, green: 0.13, blue: 0.10)
        static let warning   = PluginColor(red: 1, green: 0.55, blue: 0.45)
        static let secondary = PluginColor(red: 0.70, green: 0.70, blue: 0.74)
        static let disc      = PluginColor.white.opacity(0.14)
        static let button    = PluginColor.white.opacity(0.16)
        static let track     = PluginColor.white.opacity(0.12)
        static let selected  = PluginColor.white.opacity(0.24)
    }

    enum Copy {

        static var title            : String { String(localized: "Caffeinate", table: "CaffeinateWidget", bundle: .module) }
        static var options          : String { String(localized: "Caffeinate Options", table: "CaffeinateWidget", bundle: .module) }
        static var startLabel       : String { String(localized: "Start Caffeinate", table: "CaffeinateWidget", bundle: .module) }
        static var stopLabel        : String { String(localized: "Stop Caffeinate", table: "CaffeinateWidget", bundle: .module) }
        static var rulerLength      : String { String(localized: "Length", table: "CaffeinateWidget", bundle: .module) }
        static var rulerEnds        : String { String(localized: "Ends at", table: "CaffeinateWidget", bundle: .module) }
        static var forDuration      : String { String(localized: "For", table: "CaffeinateWidget", bundle: .module) }
        static var untilTime        : String { String(localized: "Until", table: "CaffeinateWidget", bundle: .module) }
        static var untilYouStopIt   : String { String(localized: "Until you stop it", table: "CaffeinateWidget", bundle: .module) }
        static var keepDisplayAwake : String { String(localized: "Keep display awake", table: "CaffeinateWidget", bundle: .module) }
        static var until            : String { String(localized: "until", table: "CaffeinateWidget", bundle: .module) }
        static var error            : String { String(localized: "Error", table: "CaffeinateWidget", bundle: .module) }

        /// selected is a selector segment's spoken name once it is the chosen one: colour and
        /// fill do not reach VoiceOver, so the label says it.
        static func selected(_ name: String) -> String {
            String(localized: "\(name), selected", table: "CaffeinateWidget", bundle: .module)
        }

        /// activityLabel is the activity's spoken sentence. It is a string the plugin formats, so
        /// its time is fixed at publication: the SDK has no kernel-drawn time for an accessibility
        /// label, and a locale change shows in it at the next publication.
        static func activityLabel(endsAt: Date?) -> String {
            guard let endsAt else {
                return String(localized: "Caffeinate, awake until you stop it", table: "CaffeinateWidget", bundle: .module)
            }

            return String(localized: "Caffeinate, awake until \(Format.clock(endsAt))", table: "CaffeinateWidget", bundle: .module)
        }

        /// refusedWithCode is the options page's longer line: the code is for diagnosis, so the
        /// tile only says "Error". The code is written as a string, so no digit grouping splits it.
        /// A refused change of a running session says what the ruler was moving, by the mode the
        /// selector shows: the length for For, the end for Until, and the length for the rest,
        /// since a session that is not timed has no end to speak of.
        static func refusedWithCode(
            _ failure: CaffeinateFailure,
            shown     : CaffeinateTargetKind
        ) -> String {
            switch failure {
                case .assertionRefused(let code):
                    String(localized: "Couldn't prevent sleep (error \(String(code)))", table: "CaffeinateWidget", bundle: .module)

                case .extensionRefused(let code) where shown == .until:
                    String(localized: "Couldn't change the end (error \(String(code)))", table: "CaffeinateWidget", bundle: .module)

                case .extensionRefused(let code):
                    String(localized: "Couldn't change the length (error \(String(code)))", table: "CaffeinateWidget", bundle: .module)
            }
        }
    }

    enum Format {

        /// sign is the indefinite session: it has no end, and the sign says so in any language.
        static let sign = "∞"

        /// target is the next session's length: the hours and minutes the system abbreviates for
        /// a duration, `∞` otherwise. The units come from the system's formatting, not from
        /// literals. An end time is not formatted here: the kernel draws its clock.
        static func target(_ target: CaffeinateTarget) -> String {
            guard case .duration(let minutes) = target else { return sign }

            return Self.minutes(TimeInterval(minutes * 60))
        }

        static func minutes(_ seconds: TimeInterval) -> String {
            Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        }

        /// clock is a time of day in the user's locale, as the activity's spoken sentence reads it.
        static func clock(_ date: Date) -> String {
            date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: .current))
        }
    }
}

extension PluginCaffeinateState {

    /// symbol is the glyph's look: filled while a session runs, its outline while off.
    var symbol: String {
        isActive ? glyph.filledSymbol : glyph.outlineSymbol
    }

    /// shownKind is the kind of target the options page's selector shows as chosen. Off, it is
    /// the next session's. Running, it is the session's own: one without an end is indefinite,
    /// and a timed one is shown as the kind the user last gave it, For when it was given neither
    /// (a session that was indefinite and was timed from outside the page).
    var shownKind: CaffeinateTargetKind {
        guard isActive else { return nextTarget.kind }
        guard endsAt != nil else { return .indefinite }

        return nextTarget.kind == .until ? .until : .duration
    }

    /// staleAfter is how old, in seconds, the widget's content may be when its surface becomes
    /// visible before the kernel asks the plugin for a fresh one: five minutes.
    static let staleAfter = 300.0

    /// dependsOnTheClock says the documents hold something worked out from "now": an end time
    /// (the Until ruler's range and value, the status line's clock) or the minutes a running
    /// session has left (the For ruler's value). Such content ages while nothing changes, so
    /// the widget asks to be refreshed when it is shown stale; with an indefinite session or a
    /// next length there is nothing to age.
    var dependsOnTheClock: Bool {
        shownKind == .until || (isActive && shownKind == .duration)
    }

    /// refusedToStart says the system would not hold the assertion: the session is not running,
    /// so the widget says so instead of its state.
    var refusedToStart: Bool {
        if case .assertionRefused? = failure { true } else { false }
    }

    /// refusedToExtend says a lengthening was refused: the session is as it was, so the widget
    /// keeps drawing it and only adds a warning beside it.
    var refusedToExtend: Bool {
        if case .extensionRefused? = failure { true } else { false }
    }

    /// elapsed is the start-to-end interval of a timed session, which a kernel timer counts down.
    /// An end that does not follow the start is clamped, so an odd snapshot still validates.
    var elapsed: ClosedRange<Date>? {
        guard let startedAt, let endsAt else { return nil }

        return startedAt...max(startedAt, endsAt)
    }

    /// countUpLength is how long an indefinite session's elapsed time may count. A timer node
    /// needs an end, and an indefinite session has none: a year is far past any real session, so
    /// the count never freezes, while the kernel's schedule still has an end to stop at.
    static let countUpLength: TimeInterval = 365 * 86_400

    /// countUp is the interval an indefinite session's elapsed time counts up in.
    var countUp: ClosedRange<Date>? {
        guard let startedAt, endsAt == nil else { return nil }

        return startedAt...startedAt.addingTimeInterval(Self.countUpLength)
    }

}
