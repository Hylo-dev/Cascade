//
//  PluginMailbox.swift
//  CascadeKit
//

import CascadeContracts

/// PluginMailbox holds a plugin's pending events while it handles one. Sources coalesce to their
/// latest state, in the order they first arrived; refreshes and wakes coalesce to one each;
/// actions queue in order, up to eight, because each is a tap the user made. The next event is
/// taken by urgency: the user's actions, then the world's news, then a refresh, then the
/// plugin's own wake.
struct PluginMailbox: Sendable {

    static let maximumActions = 8

    private var actions   : [PluginActionEvent] = []
    private var sources   : [PluginSourceEvent] = []
    private var hasRefresh = false
    private var hasWake    = false

    var isEmpty: Bool {
        actions.isEmpty && sources.isEmpty && !hasRefresh && !hasWake
    }

    /// post files an event and returns false only for an action past the bound.
    mutating func post(_ event: PluginEvent) -> Bool {
        switch event {
            case .refresh:
                hasRefresh = true

            case .wake:
                hasWake = true

            case .source(let state):
                if let index = sources.firstIndex(where: { $0.source == state.source }) {
                    sources[index] = state
                } else {
                    sources.append(state)
                }

            case .action(let action):
                guard actions.count < Self.maximumActions else { return false }

                actions.append(action)
        }

        return true
    }

    mutating func take() -> PluginEvent? {
        if !actions.isEmpty {
            return .action(actions.removeFirst())
        }
        if !sources.isEmpty {
            return .source(sources.removeFirst())
        }
        if hasRefresh {
            hasRefresh = false
            return .refresh
        }
        if hasWake {
            hasWake = false
            return .wake
        }

        return nil
    }

    mutating func removeAll() {
        self = PluginMailbox()
    }
}
