//
//  DisplayPresentationPreferencesStore.swift
//  CascadeKit
//

import Foundation

/// DisplayPresentationPreferencesStore owns the single UserDefaults payload
/// used by the app shell and future display services.
///
/// A malformed or future payload cannot leave routing undefined: decoding falls
/// back to the focused-display default, while a valid offline UUID remains in
/// the value until the user changes it.
@MainActor
public final class DisplayPresentationPreferencesStore {
    public static let defaultsKey = "displayPresentationPreferencesV1"

    public var preferences: DisplayPresentationPreferences {
        didSet {
            guard let payload = try? JSONEncoder().encode(preferences) else {
                return
            }
            defaults.set(payload, forKey: Self.defaultsKey)
        }
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        guard let payload = defaults.data(forKey: Self.defaultsKey),
              let decoded = try? JSONDecoder().decode(
                DisplayPresentationPreferences.self,
                from: payload
              ) else {
            preferences = DisplayPresentationPreferences()
            return
        }

        preferences = decoded
    }
}
