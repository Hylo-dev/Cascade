//
//  PluginSourceLeases.swift
//  CascadeKit
//

import CascadeContracts

/// PluginSourceLeases shares catalog sources between plugins, as the broker's shared sources
/// did: a source starts with its first lease and stops with its last. While it runs, the leases
/// keep its latest state, so a plugin that starts or restarts later is primed with it; a source
/// that stops forgets its state, which would be stale by the time it starts again.
struct PluginSourceLeases: Sendable {

    private var holders: [String: Set<PluginID>] = [:]
    private var latest : [String: PluginSourceEvent] = [:]

    /// lease adds a holder and returns true when the source must start.
    mutating func lease(
        _ source  : String,
        for plugin: PluginID
    ) -> Bool {
        let isFirst = holders[source, default: []].isEmpty
        holders[source, default: []].insert(plugin)
        return isFirst
    }

    /// release drops a holder and returns true when the source must stop.
    mutating func release(
        _ source  : String,
        for plugin: PluginID
    ) -> Bool {
        guard holders[source]?.remove(plugin) != nil, holders[source]?.isEmpty == true else { return false }

        holders[source] = nil
        latest[source]  = nil
        return true
    }

    /// record keeps the event as its source's latest state and returns who must receive it. A
    /// source with no holders is not running, so its event is dropped.
    mutating func record(_ event: PluginSourceEvent) -> Set<PluginID> {
        guard let current = holders[event.source] else { return [] }

        latest[event.source] = event
        return current
    }

    func latest(of sources: Set<String>) -> [PluginSourceEvent] {
        sources.sorted().compactMap { latest[$0] }
    }
}
