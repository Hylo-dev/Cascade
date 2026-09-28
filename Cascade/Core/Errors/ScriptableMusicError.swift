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
                "Consenti a Cascade di controllare \(source.displayName) in Impostazioni di Sistema → Privacy e sicurezza → Automazione."

            case .unavailable(let reason): reason
            case .trackChanged           : "Il brano è cambiato. Riprova sul brano attuale."
        }
    }
}
