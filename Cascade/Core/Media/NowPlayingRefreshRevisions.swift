//
//  NowPlayingRefreshRevisions.swift
//  Cascade
//

import Foundation

/// NowPlayingRefreshRevisions invalidates stale asynchronous work without
/// retaining tasks or player objects. Sequence numbers survive a reset so an
/// old process can never match a later process that uses the same source.
nonisolated struct NowPlayingRefreshRevisions {

    private var counter: UInt64 = 0
    private var latest : [ScriptableMusicSource: UInt64] = [:]

    mutating func request(_ source: ScriptableMusicSource) -> UInt64 {
        counter &+= 1
        latest[source] = counter
        return counter
    }

    func current(_ source: ScriptableMusicSource) -> UInt64? { latest[source] }

    func accepts(
        _ revision: UInt64,
        for source: ScriptableMusicSource
    ) -> Bool {
        latest[source] == revision
    }

    mutating func remove(_ source: ScriptableMusicSource) { latest[source] = nil }

    mutating func reset() { latest.removeAll() }
}
