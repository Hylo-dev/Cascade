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
    enum Node {

        static let powerMedium  = "power.medium"
        static let powerLarge   = "power.large"
        static let powerSmall   = "power.small"
        static let powerOptions = "power.options"
        static let durationDown = "duration.down"
        static let durationUp   = "duration.up"
        static let display      = "display"
        static let opener       = "options"
        static let openerLarge  = "options.large"
    }

    enum Action {

        static let start        = "caffeinate.start"
        static let stop         = "caffeinate.stop"
        static let durationDown = "caffeinate.duration.down"
        static let durationUp   = "caffeinate.duration.up"
        static let display      = "caffeinate.display"
        static let options      = "caffeinate.options"

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
    }

    /// dimmed is the look of a stepper button or a control that can do nothing right now. It
    /// stays a button: the owner ignores a step off the scale, so a stale press is harmless.
    static let dimmed = 0.35

    /// nearCap is fifteen minutes short of the longest a session may run, 24 hours: past it the
    /// stepper's plus has little or nowhere to go.
    static let nearCap: TimeInterval = (24 * 60 - 15) * 60

    enum Copy {

        static var title            : String { String(localized: "Caffeinate", table: "CaffeinateWidget", bundle: .module) }
        static var options          : String { String(localized: "Caffeinate Options", table: "CaffeinateWidget", bundle: .module) }
        static var startLabel       : String { String(localized: "Start Caffeinate", table: "CaffeinateWidget", bundle: .module) }
        static var stopLabel        : String { String(localized: "Stop Caffeinate", table: "CaffeinateWidget", bundle: .module) }
        static var shorter          : String { String(localized: "Shorter", table: "CaffeinateWidget", bundle: .module) }
        static var longer           : String { String(localized: "Longer", table: "CaffeinateWidget", bundle: .module) }
        static var start            : String { String(localized: "Start", table: "CaffeinateWidget", bundle: .module) }
        static var stop             : String { String(localized: "Stop", table: "CaffeinateWidget", bundle: .module) }
        static var display          : String { String(localized: "Display", table: "CaffeinateWidget", bundle: .module) }
        static var nextSession      : String { String(localized: "Next session", table: "CaffeinateWidget", bundle: .module) }
        static var keepDisplayAwake : String { String(localized: "Keep display awake", table: "CaffeinateWidget", bundle: .module) }
        static var until            : String { String(localized: "until", table: "CaffeinateWidget", bundle: .module) }
        static var activeFor        : String { String(localized: "active for", table: "CaffeinateWidget", bundle: .module) }
        static var error            : String { String(localized: "Error", table: "CaffeinateWidget", bundle: .module) }

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
        static func refusedWithCode(_ failure: CaffeinateFailure) -> String {
            switch failure {
                case .assertionRefused(let code):
                    String(localized: "Couldn't prevent sleep (error \(String(code)))", table: "CaffeinateWidget", bundle: .module)

                case .extensionRefused(let code):
                    String(localized: "Couldn't extend (error \(String(code)))", table: "CaffeinateWidget", bundle: .module)
            }
        }
    }

    enum Format {

        /// duration is a stepper value: the hours and minutes the system abbreviates, `∞` for an
        /// indefinite session. The units come from the system's formatting, not from literals.
        static func duration(_ duration: CaffeinateDuration) -> String {
            guard let seconds = duration.seconds else { return "∞" }

            return minutes(seconds)
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

    /// remaining is the time a timed session has left when the document is built, nil for an
    /// indefinite one. It is read once per publication: the dimming it decides is a hint, since
    /// the owner enforces the cap whatever is pressed.
    func remaining(at now: Date) -> TimeInterval? {
        endsAt.map { $0.timeIntervalSince(now) }
    }
}
