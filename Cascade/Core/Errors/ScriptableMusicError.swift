//
//  ScriptableMusicError.swift
//  Cascade
//

import Foundation

/// ScriptableMusicError carries actionable failures across the worker boundary.
nonisolated enum ScriptableMusicError: LocalizedError, Sendable, Equatable {

    case permissionRequired(ScriptableMusicSource)
    case unavailable       (String)
    case trackChanged

    var errorDescription: String? {
        switch self {
            case .permissionRequired(let source):
                String(localized: "Allow Cascade to control \(source.displayName) in System Settings → Privacy & Security → Automation.")

            case .unavailable(let reason): reason
            case .trackChanged           : String(localized: "The track changed. Try again on the current track.")
        }
    }
}
