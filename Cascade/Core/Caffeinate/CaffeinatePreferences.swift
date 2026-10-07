//
//  CaffeinatePreferences.swift
//  Cascade
//

import CascadeContracts
import Foundation

/// CaffeinatePreferences is what Caffeinate remembers between launches: the length of the next
/// session, whether a session also keeps the display awake, the glyph and the global shortcut. The
/// service reads them once when it is created and, from its own queue, writes the first three only
/// when the user changes them, so the store is never touched while a session just runs. The
/// shortcut is the exception: Cascade's main actor writes it, when the user records a new one, and
/// the service never touches it. It is a class-bound protocol so the service can keep one instance
/// and write through it.
nonisolated protocol CaffeinatePreferences: AnyObject, Sendable {

    var nextDuration     : CaffeinateDuration  { get set }
    var keepsDisplayAwake: Bool                { get set }
    var glyph            : CaffeinateGlyph     { get set }

    /// The global shortcut. `nil` means the user turned it off, which is not the same as never
    /// having chosen one (that is `CaffeinateShortcut.default`).
    var shortcut         : CaffeinateShortcut? { get set }
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
        static let shortcut          = "caffeinate.shortcut"
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

    /// The shortcut is JSON in a `Data`. Three states share one key: absent means never chosen
    /// (the default), empty data means switched off, anything else is the encoded shortcut, and
    /// data that no longer decodes, or decodes to a key with no ⌘⌃⌥ (which would steal that key, or
    /// its capital, everywhere), falls back to the default rather than silently disabling it.
    var shortcut: CaffeinateShortcut? {
        get {
            guard let data = defaults.data(forKey: Key.shortcut) else { return .default }
            guard !data.isEmpty else { return nil }

            guard
                let shortcut = try? JSONDecoder().decode(CaffeinateShortcut.self, from: data),
                shortcut.hasModifier
            else { return .default }

            return shortcut
        }
        set {
            let data = newValue.flatMap { try? JSONEncoder().encode($0) } ?? Data()

            defaults.set(data, forKey: Key.shortcut)
        }
    }
}
