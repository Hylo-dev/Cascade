//
//  CaffeinateTarget.swift
//  CascadeKit
//

import Foundation

/// CaffeinateTargetKind is the three ways a keep-awake session can be asked to end, without the
/// value: it is what the options page's selector chooses between. The raw value is the wire name
/// and the suffix of the `caffeinate.mode.*` actions.
public enum CaffeinateTargetKind: String, CaseIterable, Hashable, Sendable {

    case indefinite
    case duration
    case until
}

/// CaffeinateTarget is when a keep-awake session ends: never (until the user stops it), after a
/// length of time, or at a time of day. It is a value on the one scale the options page's ruler
/// walks, a tick every 15 minutes, so the control, the wire and the native owner agree on what
/// is valid; `init?(kind:value:)` is the one place a stranger's number becomes a target, and it
/// rejects whatever is off the scale instead of letting it reach an assertion.
///
/// A duration is 15 to 1440 minutes: 1440 minutes is 86 400 s, the longest timeout IOKit accepts
/// for a power assertion. An end time is a minute of the local day, 0 to 1425, which says "18:00"
/// and nothing about which day, since the day depends on when the session starts: the session
/// ends at the next occurrence, never less than 15 minutes ahead.
public enum CaffeinateTarget: Hashable, Sendable {

    case indefinite
    case duration(minutes: Int)
    case until(minuteOfDay: Int)

    public static let step           = 15
    public static let maximumMinutes = 1440
    public static let minutesPerDay  = 1440

    /// minimumLead is how far ahead an end time must be: fifteen minutes, one tick of the ruler.
    public static let minimumLead: TimeInterval = TimeInterval(step * 60)

    /// shortestLead is the least an end may be ahead of the start when the 15-minute rule cannot
    /// be met within a day: one minute, the floor `setUntil` applies to a chosen instant.
    public static let shortestLead: TimeInterval = 60

    /// maximumLength is the longest a session may be asked to run, one day: IOKit's longest
    /// timeout, and the end of the ruler.
    public static let maximumLength: TimeInterval = TimeInterval(maximumMinutes * 60)

    /// init?(kind:value:) builds a target from its wire form: the value is a count of minutes for
    /// a duration, a minute of the day for an end time and 0 for an indefinite session. Anything
    /// off the scale answers nil.
    public init?(
        kind : CaffeinateTargetKind,
        value: Int
    ) {
        switch kind {
            case .indefinite:
                guard value == 0 else { return nil }

                self = .indefinite

            case .duration:
                guard Self.isValid(minutes: value) else { return nil }

                self = .duration(minutes: value)

            case .until:
                guard Self.isValid(minuteOfDay: value) else { return nil }

                self = .until(minuteOfDay: value)
        }
    }

    public static func isValid(minutes: Int) -> Bool {
        minutes >= step && minutes <= maximumMinutes && minutes % step == 0
    }

    public static func isValid(minuteOfDay: Int) -> Bool {
        minuteOfDay >= 0 && minuteOfDay < minutesPerDay && minuteOfDay % step == 0
    }

    /// isValid says the target sits on the scale. A case built by hand can be off it; one that
    /// came through `init?(kind:value:)` never is.
    public var isValid: Bool {
        switch self {
            case .indefinite              : true
            case .duration(let minutes)   : Self.isValid(minutes: minutes)
            case .until(let minuteOfDay)  : Self.isValid(minuteOfDay: minuteOfDay)
        }
    }

    public var kind: CaffeinateTargetKind {
        switch self {
            case .indefinite: .indefinite
            case .duration  : .duration
            case .until     : .until
        }
    }

    /// value is the number the wire carries beside the kind.
    public var value: Int {
        switch self {
            case .indefinite              : 0
            case .duration(let minutes)   : minutes
            case .until(let minuteOfDay)  : minuteOfDay
        }
    }

    /// end is when a session that starts at `start` ends, nil for an indefinite one. A duration
    /// ends that many minutes later. An end time ends at the next occurrence of that local
    /// wall-clock time that is at least 15 minutes after the start, found in the calendar's time
    /// zone so a daylight saving change moves the end with the clock on the wall: on a day that
    /// is 23 or 25 hours long the session is 23 or 25 hours long, and a time the clock skips
    /// ends when the clock next shows a later one. The result is never more than a day past the
    /// start, since IOKit would cut a longer assertion short of the published end: when the next
    /// occurrence is further away, the previous one is used if it is at least a minute ahead
    /// (shorter than 15 minutes, but on the clock), and the cap itself only as a last resort.
    public func end(
        startingAt start: Date,
        calendar        : Calendar
    ) -> Date? {
        switch self {
            case .indefinite:
                return nil

            case .duration(let minutes):
                return start.addingTimeInterval(TimeInterval(minutes * 60))

            case .until(let minuteOfDay):
                // nextDate(after:) is strictly after, so the earliest acceptable instant is
                // nudged back by a millisecond to be accepted itself.
                let earliest = start.addingTimeInterval(Self.minimumLead - 0.001)
                let latest   = start.addingTimeInterval(Self.maximumLength)
                let wanted   = DateComponents(
                    hour  : minuteOfDay / 60,
                    minute: minuteOfDay % 60,
                    second: 0
                )
                guard let next = calendar.nextDate(
                    after         : earliest,
                    matching      : wanted,
                    matchingPolicy: .nextTime
                ) else { return latest }

                if next <= latest { return next }

                // The next occurrence is more than a day away (a start just short of the 15
                // minutes, or the 25-hour day when the clocks go back). The previous one is
                // still on the wall clock's grid, and is taken when it is at least a minute
                // ahead; only when it is not, the cap itself is the end.
                if let previous = calendar.nextDate(
                    after         : next,
                    matching      : wanted,
                    matchingPolicy: .nextTime,
                    direction     : .backward
                ), previous.timeIntervalSince(start) >= Self.shortestLead {
                    return previous
                }

                return latest
        }
    }
}
