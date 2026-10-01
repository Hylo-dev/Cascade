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
        var sourceStarts: [String] = []
        var sourceStops : [String] = []
    }

    private let state       = Mutex(State())
    private let onLoss       : @Sendable () -> Void
    private let onSourceEvent: @Sendable (PluginSourceEvent) -> Void
    private let losesOnStart : Bool

    /// init makes a link; one that `losesOnStart` dies the moment it is asked to load a plugin,
    /// on the caller's thread, as a host may crash while the handshake is still being finished.
    init(
        losesOnStart : Bool,
        onLoss       : @escaping @Sendable () -> Void,
        onSourceEvent: @escaping @Sendable (PluginSourceEvent) -> Void
    ) {
        self.losesOnStart  = losesOnStart
        self.onLoss        = onLoss
        self.onSourceEvent = onSourceEvent
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

    var sourceStarts: [String] {
        state.withLock { $0.sourceStarts }
    }

    var sourceStops: [String] {
        state.withLock { $0.sourceStops }
    }

    func hello(_ reply: @escaping @Sendable (PluginHostIncarnation?) -> Void) {
        state.withLock { $0.greeting = reply }
    }

    func start(
        _ plugin  : PluginID,
        entryPoint: String
    ) {
        state.withLock { $0.starts.append(plugin) }
        if losesOnStart {
            onLoss()
        }
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

    func startSource(_ name: String) {
        state.withLock { $0.sourceStarts.append(name) }
    }

    func stopSource(_ name: String) {
        state.withLock { $0.sourceStops.append(name) }
    }

    /// emit sends a source state from this host, as PluginHost's client proxy would.
    func emit(_ event: PluginSourceEvent) {
        onSourceEvent(event)
    }

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
