//
//  CaffeinatePreferences.swift
//  Cascade
//

import CascadeContracts
import Foundation

/// CaffeinatePreferences is what Caffeinate remembers between launches: the length of the next
/// session, whether a session also keeps the display awake, and the glyph. The service reads them
/// once when it is created and writes one only when the user changes it, so the store is never
/// touched while a session just runs. It is a class-bound protocol so the service can keep one
/// instance and write through it, and the service calls it only from its own queue.
nonisolated protocol CaffeinatePreferences: AnyObject, Sendable {

    var nextDuration     : CaffeinateDuration { get set }
    var keepsDisplayAwake: Bool               { get set }
    var glyph            : CaffeinateGlyph    { get set }
}

/// UserDefaultsCaffeinatePreferences keeps the preferences in `UserDefaults`. The next duration
/// is stored as its wire minutes, 0 for indefinite, so it shares the scale's one definition of
/// what is valid: a stored value off the scale, or one that was never written, falls back to the
/// default instead of reaching an assertion. `UserDefaults` is thread-safe, which is why this
/// class can be shared without a lock of its own.
nonisolated final class UserDefaultsCaffeinatePreferences: CaffeinatePreferences {

    static let defaultDuration: CaffeinateDuration = .minutes(60)

    private enum Key {

        static let nextDuration      = "caffeinate.nextDuration"
        static let keepsDisplayAwake = "caffeinate.keepsDisplayAwake"
        static let glyph             = "caffeinate.glyph"
    }

    /// UserDefaults is documented as thread-safe but not marked Sendable by the SDK.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var nextDuration: CaffeinateDuration {
        get {
            // integer(forKey:) answers 0 for a missing key, which is also indefinite's wire value.
            guard defaults.object(forKey: Key.nextDuration) != nil else { return Self.defaultDuration }

            return CaffeinateDuration(wireMinutes: defaults.integer(forKey: Key.nextDuration)) ?? Self.defaultDuration
        }
        set { defaults.set(newValue.wireMinutes, forKey: Key.nextDuration) }
    }

    var keepsDisplayAwake: Bool {
        get {
            guard defaults.object(forKey: Key.keepsDisplayAwake) != nil else { return true }

            return defaults.bool(forKey: Key.keepsDisplayAwake)
        }
        set { defaults.set(newValue, forKey: Key.keepsDisplayAwake) }
    }

    var glyph: CaffeinateGlyph {
        get { defaults.string(forKey: Key.glyph).flatMap(CaffeinateGlyph.init(rawValue:)) ?? .cupHeatWaves }
        set { defaults.set(newValue.rawValue, forKey: Key.glyph) }
    }
}
