//
//  PluginMailbox.swift
//  CascadeKit
//

import CascadeContracts

/// PluginMailbox holds a plugin's pending events while it handles one. Sources coalesce to their
/// latest state, in the order they first arrived; refreshes and wakes coalesce to one each;
/// actions queue in order, up to eight, because each is a tap the user made. An action keeps
/// the renderer's request and the moment it was accepted, so the kernel can still refuse it
/// when its turn comes. The next item is taken by urgency: the user's actions, then the world's
/// news, then a refresh, then the plugin's own wake.
struct PluginMailbox: Sendable {

    /// Action is an accepted action waiting for its turn.
    struct Action: Equatable, Sendable {

        let event   : PluginActionEvent
        let request : PluginActionRequest
        let postedAt: Duration
    }

    /// Item is what `take` hands out: an event, or an action with what refusing it needs.
    enum Item: Equatable, Sendable {

        case event(PluginEvent)
        case action(Action)
    }

    static let maximumActions = 8

    private var actions   : [Action] = []
    private var sources   : [PluginSourceEvent] = []
    private var hasRefresh = false
    private var hasWake    = false

    var isEmpty: Bool {
        actions.isEmpty && sources.isEmpty && !hasRefresh && !hasWake
    }

    /// post files a refresh, a wake or a source state. An action needs its request, so it goes
    /// through `queue`, and one posted here is ignored.
    mutating func post(_ event: PluginEvent) {
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

            case .action:
                break
        }
    }

    /// queue files an action and returns false past the bound.
    mutating func queue(_ action: Action) -> Bool {
        guard actions.count < Self.maximumActions else { return false }

        actions.append(action)
        return true
    }

    mutating func take() -> Item? {
        if !actions.isEmpty {
            return .action(actions.removeFirst())
        }
        if !sources.isEmpty {
            return .event(.source(sources.removeFirst()))
        }
        if hasRefresh {
            hasRefresh = false
            return .event(.refresh)
        }
        if hasWake {
            hasWake = false
            return .event(.wake)
        }

        return nil
    }

    mutating func removeAll() {
        self = PluginMailbox()
    }
}
