//
//  SharedHostExecutor.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Synchronization

/// SharedHostExecutor runs every first-party plugin in the one PluginHost process, through a
/// transport. It is available from a completed handshake until that host is lost, and the
/// kernel dispatches only while it is: a dispatch that races a loss is reported lost at once,
/// so the kernel's watchdog never times a host that is not there. Each handshake loads every
/// plugin the kernel started, and the kernel primes them all.
///
/// Stopping a plugin inside `handle()` kills the incarnation of the handshake, the only way to
/// end a hung call; the next host loads every plugin but that one. A dispatch in flight when the
/// host dies fails, which counts against its plugin, unless the kernel killed the host, when it
/// is lost and counts against nobody. The supervisor decides when to connect again.
public final class SharedHostExecutor: PluginExecutor {

    private enum Phase {

        case disconnected
        case connecting
        case ready
        case waiting
    }

    private struct Dispatch {

        let plugin    : PluginID
        let completion: @Sendable (PluginExecutionResult) -> Void
    }

    /// Greeting is what a completed handshake hands over once the lock is released.
    private struct Greeting {

        let link    : any PluginHostLink
        let plugins : [(PluginID, String)]
        let observer: (@Sendable (PluginExecutorEvent) -> Void)?
    }

    /// Ending is what a lost host leaves to report once the lock is released.
    private struct Ending {

        let link      : (any PluginHostLink)?
        let dispatches: [Dispatch]
        let outcome   : PluginExecutionResult
        let observer  : (@Sendable (PluginExecutorEvent) -> Void)?
        let delay     : Duration?
    }

    private struct State {

        var phase        = Phase.disconnected
        var generation   : UInt64 = 0
        var link         : (any PluginHostLink)?
        var plugins      : [PluginID: String] = [:]
        var inFlight     : [UInt64: Dispatch] = [:]
        var lastDispatch : UInt64 = 0
        var isKilling    = false
        var sawBreak     = false
        var observer     : (@Sendable (PluginExecutorEvent) -> Void)?
        var supervisor   = PluginHostSupervisor()
    }

    private let state    = Mutex(State())
    private let transport: any PluginTransport
    private let clock    : @Sendable () -> Duration
    private let schedule : @Sendable (Duration, @escaping @Sendable () -> Void) -> Void

    public convenience init(transport: any PluginTransport) {
        self.init(
            transport: transport,
            clock    : { .seconds(ProcessInfo.processInfo.systemUptime) },
            schedule : { delay, work in
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + delay / .seconds(1), execute: work)
            }
        )
    }

    init(
        transport: any PluginTransport,
        clock    : @escaping @Sendable () -> Duration,
        schedule : @escaping @Sendable (Duration, @escaping @Sendable () -> Void) -> Void
    ) {
        self.transport = transport
        self.clock     = clock
        self.schedule  = schedule
    }

    public func observe(_ handler: @escaping @Sendable (PluginExecutorEvent) -> Void) {
        let isReady = state.withLock { state in
            state.observer = handler
            return state.phase == .ready
        }

        handler(isReady ? .available : .unavailable)
    }

    public func start(
        _ plugin  : PluginID,
        entryPoint: String
    ) {
        let link = state.withLock { state in
            state.plugins[plugin] = entryPoint
            return state.phase == .ready ? state.link : nil
        }

        link?.start(plugin, entryPoint: entryPoint)
        connectIfNeeded()
    }

    public func dispatch(
        _ event   : PluginEvent,
        to plugin : PluginID,
        completion: @escaping @Sendable (PluginExecutionResult) -> Void
    ) {
        let sent = state.withLock { state -> (link: any PluginHostLink, id: UInt64)? in
            guard state.phase == .ready, let link = state.link else { return nil }

            state.lastDispatch += 1

            let id = state.lastDispatch
            state.inFlight[id] = Dispatch(plugin: plugin, completion: completion)
            return (link, id)
        }
        guard let sent else {
            completion(.lost)
            return
        }

        sent.link.handle(event, for: plugin) { [weak self] result in
            self?.finish(sent.id, with: result)
        }
    }

    public func stop(_ plugin: PluginID) {
        let link = state.withLock { state -> (any PluginHostLink)? in
            state.plugins[plugin] = nil
            guard state.phase == .ready, state.inFlight.values.contains(where: { $0.plugin == plugin }) else { return nil }

            state.isKilling = true
            return state.link
        }

        link?.kill()
    }

    /// finish completes one dispatch. A missing answer means the connection broke: the dispatch
    /// is lost when the kernel killed the host, and fails otherwise, and the break is remembered
    /// so the loss that follows still counts as a crash with a plugin inside.
    private func finish(
        _ id       : UInt64,
        with result: PluginExecutionResult?
    ) {
        let done = state.withLock { state -> (Dispatch, PluginExecutionResult)? in
            guard let dispatch = state.inFlight.removeValue(forKey: id) else { return nil }

            if result == nil && !state.isKilling {
                state.sawBreak = true
            }
            return (dispatch, result ?? (state.isKilling ? .lost : PluginExecutionResult(outcome: .failed, cpuTime: .zero)))
        }

        if let done {
            done.0.completion(done.1)
        }
    }

    private func connectIfNeeded() {
        let generation = state.withLock { state -> UInt64? in
            guard state.phase == .disconnected, !state.supervisor.hasGivenUp, !state.plugins.isEmpty else { return nil }

            state.phase       = .connecting
            state.generation += 1
            return state.generation
        }
        guard let generation else { return }

        let link = transport.connect { [weak self] in
            self?.lose(generation)
        }
        state.withLock { state in
            if state.generation == generation, state.phase == .connecting {
                state.link = link
            }
        }
        link.hello { [weak self] incarnation in
            self?.greet(generation, incarnation)
        }
    }

    private func greet(
        _ generation: UInt64,
        _ incarnation: PluginHostIncarnation?
    ) {
        guard incarnation != nil else {
            lose(generation)
            return
        }

        let now      = clock()
        let greeting = state.withLock { state -> Greeting? in
            guard state.generation == generation, state.phase == .connecting, let link = state.link else { return nil }

            state.phase = .ready
            state.supervisor.launched(at: now)
            return Greeting(
                link    : link,
                plugins : state.plugins.sorted { $0.key.rawValue < $1.key.rawValue }.map { ($0.key, $0.value) },
                observer: state.observer
            )
        }
        guard let greeting else { return }

        for (plugin, entryPoint) in greeting.plugins {
            greeting.link.start(plugin, entryPoint: entryPoint)
        }
        greeting.observer?(.available)
    }

    /// lose ends one host. The engine hears that the host is unavailable before it hears about
    /// the dispatches the loss ended, so the plugins it primes again wait for the next host.
    private func lose(_ generation: UInt64) {
        let now    = clock()
        let ending = state.withLock { state -> Ending? in
            guard state.generation == generation, state.phase == .connecting || state.phase == .ready else { return nil }

            let cause: PluginHostSupervisor.Loss = state.isKilling
                ? .killed
                : (state.inFlight.isEmpty && !state.sawBreak ? .crashedIdle : .crashed)
            let ending = Ending(
                link      : state.link,
                dispatches: Array(state.inFlight.values),
                outcome   : state.isKilling ? .lost : PluginExecutionResult(outcome: .failed, cpuTime: .zero),
                observer  : state.observer,
                delay     : state.supervisor.lost(cause, at: now)
            )

            state.inFlight.removeAll()
            state.link      = nil
            state.isKilling = false
            state.sawBreak  = false
            state.phase     = ending.delay == nil ? .disconnected : .waiting
            return ending
        }
        guard let ending else { return }

        ending.link?.invalidate()
        ending.observer?(.unavailable)
        for dispatch in ending.dispatches {
            dispatch.completion(ending.outcome)
        }

        if let delay = ending.delay {
            schedule(delay) { [weak self] in
                self?.retry(generation)
            }
        }
    }

    private func retry(_ generation: UInt64) {
        state.withLock { state in
            if state.generation == generation, state.phase == .waiting {
                state.phase = .disconnected
            }
        }

        connectIfNeeded()
    }
}
