//
//  ScriptablePlayerTarget.swift
//  Cascade
//

import CascadeKit
import Foundation

/// ScriptablePlayerTarget addresses an already running process. PID addressing
/// makes it impossible for a metadata query to launch an absent player.
nonisolated struct ScriptablePlayerTarget: Equatable, Sendable {
    let source           : ScriptableMusicSource
    let processIdentifier: Int32
}
