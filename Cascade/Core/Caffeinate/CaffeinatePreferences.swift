//
//  CaffeinatePreferences.swift
//  Cascade
//

import CascadeContracts
import Foundation

/// CaffeinatePreferences is what Caffeinate remembers between launches: how the next session
/// ends, the last duration and the last end time the user chose (so switching mode brings the
/// last value of that mode back), whether a session also keeps the display awake, the glyph and the global shortcut. The
/// service reads them once when it is created and, from its own queue, writes the first three only
/// when the user changes them, so the store is never touched while a session just runs. The
/// shortcut is the exception: Cascade's main actor writes it, when the user records a new one, and
/// the service never touches it. It is a class-bound protocol so the service can keep one instance
/// and write through it.
nonisolated protocol CaffeinatePreferences: AnyObject, Sendable {

    var nextTarget       : CaffeinateTarget    { get set }
    var keepsDisplayAwake: Bool                { get set }
    var glyph            : CaffeinateGlyph     { get set }

    /// The last duration, in minutes, and the last end time, as a minute of the local day, the
    /// user chose. `nil` means never chosen: the service then falls back to an hour and to the
    /// next full hour, which needs its clock and its calendar, so the default is not stored here.
    var lastDurationMinutes : Int? { get set }
    var lastUntilMinuteOfDay: Int? { get set }

    /// The global shortcut. `nil` means the user turned it off, which is not the same as never
    /// having chosen one (that is `CaffeinateShortcut.default`).
    var shortcut         : CaffeinateShortcut? { get set }
}

/// UserDefaultsCaffeinatePreferences keeps the preferences in `UserDefaults`. The target is
/// stored as its wire pair, a kind name and a number, so it shares the contract's one definition
/// of what is valid: a stored value off the scale, or one that was never written, falls back to
/// the default (indefinite) instead of reaching an assertion. `UserDefaults` is thread-safe,
/// which is why this class can be shared without a lock of its own.
nonisolated final class UserDefaultsCaffeinatePreferences: CaffeinatePreferences {

    private enum Key {

        static let targetKind        = "caffeinate.nextTarget.kind"
        static let targetValue       = "caffeinate.nextTarget.value"
        static let lastDuration      = "caffeinate.lastDuration"
        static let lastUntil         = "caffeinate.lastUntil"
        static let keepsDisplayAwake = "caffeinate.keepsDisplayAwake"
        static let glyph             = "caffeinate.glyph"
        static let shortcut          = "caffeinate.shortcut"
    }

    /// UserDefaults is documented as thread-safe but not marked Sendable by the SDK.
    nonisolated(unsafe) private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var nextTarget: CaffeinateTarget {
        get {
            guard
                let name = defaults.string(forKey: Key.targetKind),
                let kind = CaffeinateTargetKind(rawValue: name)
            else { return .indefinite }

            return CaffeinateTarget(kind: kind, value: defaults.integer(forKey: Key.targetValue)) ?? .indefinite
        }
        set {
            defaults.set(newValue.kind.rawValue, forKey: Key.targetKind)
            defaults.set(newValue.value, forKey: Key.targetValue)
        }
    }

    var lastDurationMinutes: Int? {
        get {
            guard defaults.object(forKey: Key.lastDuration) != nil else { return nil }

            let minutes = defaults.integer(forKey: Key.lastDuration)
            return CaffeinateTarget.isValid(minutes: minutes) ? minutes : nil
        }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.lastDuration) } else { defaults.removeObject(forKey: Key.lastDuration) }
        }
    }

    var lastUntilMinuteOfDay: Int? {
        get {
            guard defaults.object(forKey: Key.lastUntil) != nil else { return nil }

            let minuteOfDay = defaults.integer(forKey: Key.lastUntil)
            return CaffeinateTarget.isValid(minuteOfDay: minuteOfDay) ? minuteOfDay : nil
        }
        set {
            if let newValue { defaults.set(newValue, forKey: Key.lastUntil) } else { defaults.removeObject(forKey: Key.lastUntil) }
        }
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
