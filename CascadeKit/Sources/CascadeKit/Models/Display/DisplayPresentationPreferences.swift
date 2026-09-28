//
//  DisplayPresentationPreferences.swift
//  CascadeKit
//

import Foundation

/// DisplayIdentity is the stable UUID-backed identity of a physical display.
///
/// CoreGraphics display identifiers only last for the current session. Keeping
/// the UUID as an opaque string lets a fixed routing choice and a software-notch
/// style survive reconnection without exposing CoreGraphics in persisted data.
@frozen
public nonisolated struct DisplayIdentity: RawRepresentable, Hashable, Codable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// ExternalNotchStyle describes the compact chrome used when no hardware notch
/// dictates the shape.
public nonisolated enum ExternalNotchStyle: String, Codable, Equatable, Sendable {
    case notch
    case dynamicIsland
}

/// LiveActivityDisplayMode describes which connected displays receive compact
/// copies of shared Live Activities.
public nonisolated enum LiveActivityDisplayMode: Codable, Equatable, Sendable {
    case allDisplays
    case focusedDisplay
    case fixedDisplay(DisplayIdentity)
}

/// DisplayPresentationPreferences is the complete persisted display policy.
///
/// Missing style entries deliberately resolve to `notch`, so newly connected
/// displays gain a conservative shape without rewriting the saved payload.
public nonisolated struct DisplayPresentationPreferences: Codable, Equatable, Sendable {
    public let activityMode: LiveActivityDisplayMode
    public let styles      : [DisplayIdentity: ExternalNotchStyle]

    public init(
        activityMode: LiveActivityDisplayMode = .focusedDisplay,
        styles      : [DisplayIdentity: ExternalNotchStyle] = [:]
    ) {
        self.activityMode = activityMode
        self.styles       = styles
    }

    /// style returns the saved software-notch shape or the product default for
    /// a display that has never had an explicit choice.
    public func style(for identity: DisplayIdentity) -> ExternalNotchStyle {
        styles[identity] ?? .notch
    }
}

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
