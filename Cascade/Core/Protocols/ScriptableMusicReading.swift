//
//  ScriptableMusicReading.swift
//  Cascade
//

import CascadeKit
import Foundation

/// ScriptableMusicReading isolates AppleEvents and artwork from UI ownership.
nonisolated protocol ScriptableMusicReading: ScriptableMusicCommandSending {
    func read(_ target: ScriptablePlayerTarget) async throws -> NowPlayingSnapshot?
    func requestAccess(_ target: ScriptablePlayerTarget) async throws
    func reset() async
    func discardArtwork(_ source: ScriptableMusicSource) async
}
