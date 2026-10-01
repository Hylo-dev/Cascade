//
//  FakeHostLink.swift
//  CascadeKit
//

import CascadeContracts
import Synchronization

@testable import CascadePluginEngine

/// FakeHostLink is a connection to a host the test plays: it records what the executor sent and
/// answers only when told to.
final class FakeHostLink: PluginHostLink {

    private struct State {

        var greeting: (@Sendable (PluginHostIncarnation?) -> Void)?
        var starts  : [PluginID] = []
        var handled : [(event: PluginEvent, plugin: PluginID, reply: @Sendable (PluginExecutionResult?) -> Void)] = []
        var killed  = false
    }

    private let state  = Mutex(State())
    private let onLoss : @Sendable () -> Void

    init(onLoss: @escaping @Sendable () -> Void) {
        self.onLoss = onLoss
    }

    var starts: [PluginID] {
        state.withLock { $0.starts }
    }

    var handled: [PluginEvent] {
        state.withLock { $0.handled.map(\.event) }
    }

    var wasKilled: Bool {
        state.withLock { $0.killed }
    }

    func hello(_ reply: @escaping @Sendable (PluginHostIncarnation?) -> Void) {
        state.withLock { $0.greeting = reply }
    }

    func start(
        _ plugin  : PluginID,
        entryPoint: String
    ) {
        state.withLock { $0.starts.append(plugin) }
    }

    func handle(
        _ event   : PluginEvent,
        for plugin: PluginID,
        reply     : @escaping @Sendable (PluginExecutionResult?) -> Void
    ) {
        state.withLock { $0.handled.append((event, plugin, reply)) }
    }

    func kill() {
        state.withLock { $0.killed = true }
    }

    func invalidate() {}

    /// greet completes the handshake with a made-up incarnation.
    func greet() {
        let reply = state.withLock { $0.greeting }
        reply?(PluginHostIncarnation(pid: 1, startSeconds: 0, startMicroseconds: 0, path: "/fake"))
    }

    /// answer replies to the dispatch at `index`, nil standing for a broken connection.
    func answer(
        _ index: Int,
        with result: PluginExecutionResult?
    ) {
        let reply = state.withLock { $0.handled[index].reply }
        reply(result)
    }

    /// die reports the host's death, as XPC's interruption handler would.
    func die() {
        onLoss()
    }
}
