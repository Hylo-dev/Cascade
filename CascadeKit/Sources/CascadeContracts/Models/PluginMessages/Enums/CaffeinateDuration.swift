//
//  CaffeinateDuration.swift
//  CascadeKit
//

import Foundation

/// CaffeinateDuration is the length of a keep-awake session, on the one scale the stepper walks:
/// indefinite, then 15 to 1440 minutes in steps of 15. A scale rather than a free number keeps
/// the control, the wire and the native owner in agreement, and 1440 minutes is 86 400 s, the
/// longest timeout IOKit accepts for a power assertion. On the wire it is a count of minutes,
/// with 0 standing for indefinite, so a stale or hostile value is rejected by `init?(wireMinutes:)`
/// instead of reaching the assertion.
public enum CaffeinateDuration: Hashable, Sendable {

    case indefinite
    case minutes(Int)

    public static let step           = 15
    public static let maximumMinutes = 1440

    /// init?(wireMinutes:) reads a count of minutes off the wire: 0 is indefinite, anything else
    /// must sit on the scale.
    public init?(wireMinutes: Int) {
        if wireMinutes == 0 {
            self = .indefinite
            return
        }
        guard wireMinutes >= Self.step,
              wireMinutes <= Self.maximumMinutes,
              wireMinutes % Self.step == 0
        else { return nil }

        self = .minutes(wireMinutes)
    }

    public var wireMinutes: Int {
        switch self {
            case .indefinite       : 0
            case .minutes(let value): value
        }
    }

    /// seconds is the length in seconds, or nil for an indefinite session.
    public var seconds: TimeInterval? {
        switch self {
            case .indefinite       : nil
            case .minutes(let value): TimeInterval(value * 60)
        }
    }

    /// steppedUp is the next longer duration, or nil at the top of the scale. Indefinite sits at
    /// the bottom, so the first step up from it is the shortest real duration.
    public func steppedUp() -> CaffeinateDuration? {
        switch self {
            case .indefinite:
                .minutes(Self.step)

            case .minutes(let value):
                value + Self.step <= Self.maximumMinutes ? .minutes(value + Self.step) : nil
        }
    }

    /// steppedDown is the next shorter duration, or nil at the bottom of the scale: the shortest
    /// real duration steps down to indefinite, and indefinite has nothing below it.
    public func steppedDown() -> CaffeinateDuration? {
        switch self {
            case .indefinite:
                nil

            case .minutes(let value):
                value - Self.step >= Self.step ? .minutes(value - Self.step) : .indefinite
        }
    }

    /// timeLeft puts the time that remains on the scale, rounding up so a running session never
    /// shows less than it still has, and clamping to 15...1440 minutes.
    public static func timeLeft(_ remaining: TimeInterval) -> CaffeinateDuration {
        let stepSeconds = TimeInterval(step * 60)
        let steps       = (remaining / stepSeconds).rounded(.up)
        let clamped     = min(Double(maximumMinutes / step), max(1, steps.isFinite ? steps : 1))

        return .minutes(Int(clamped) * step)
    }
}
