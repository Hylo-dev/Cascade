//
//  ScriptableMusicCommandSending.swift
//  Cascade
//

import CascadeKit
import Foundation

/// ScriptableMusicCommandSending lets playback use a worker independent of
/// metadata and artwork, so a slow read cannot hold a user's command in line.
nonisolated protocol ScriptableMusicCommandSending: Sendable {
    func send(
        _ command: MediaCommand,
        to target: ScriptablePlayerTarget,
        expectedTrack: String?
    ) async throws
}
