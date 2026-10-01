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
/// is lost and counts against nobody. A call answered with nothing means the connection broke,
/// so it is the loss itself, whatever order XPC reports the two in. The supervisor decides when
/// to connect again.
///
/// Every call out, to the link, the engine or a completion, is decided under the lock and queued
/// in the outbox there, then run in that order once the lock is released. A host lost on another
/// thread while a handshake is being finished therefore reaches the engine after that handshake's
/// `available`, never before it, and the engine always ends on the host's true state.
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

    private struct State {

        var phase       = Phase.disconnected
        var generation  : UInt64 = 0
        var link        : (any PluginHostLink)?
        var plugins     : [PluginID: String] = [:]
        var inFlight    : [UInt64: Dispatch] = [:]
        var lastDispatch: UInt64 = 0
        var isKilling   = false
        var observer    : (@Sendable (PluginExecutorEvent) -> Void)?
        var supervisor  = PluginHostSupervisor()
        var outbox      : [@Sendable () -> Void] = []
        var isDraining  = false
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
        state.withLock { state in
            let event: PluginExecutorEvent = state.phase == .ready ? .available : .unavailable

            state.observer = handler
            state.outbox.append { handler(event) }
        }
        drain()
    }

    public func start(
        _ plugin  : PluginID,
        entryPoint: String
    ) {
        state.withLock { state in
            state.plugins[plugin] = entryPoint
            if state.phase == .ready, let link = state.link {
                state.outbox.append { link.start(plugin, entryPoint: entryPoint) }
            }
        }
        drain()
        connectIfNeeded()
    }

    public func dispatch(
        _ event   : PluginEvent,
        to plugin : PluginID,
        completion: @escaping @Sendable (PluginExecutionResult) -> Void
    ) {
        state.withLock { state in
            guard state.phase == .ready, let link = state.link else {
                state.outbox.append { completion(.lost) }
                return
            }

            state.lastDispatch += 1

            let id         = state.lastDispatch
            let generation = state.generation
            let reply: @Sendable (PluginExecutionResult?) -> Void = { [weak self] result in
                self?.finish(id, of: generation, with: result)
            }
            state.inFlight[id] = Dispatch(plugin: plugin, completion: completion)
            state.outbox.append { link.handle(event, for: plugin, reply: reply) }
        }
        drain()
    }

    public func stop(_ plugin: PluginID) {
        state.withLock { state in
            state.plugins[plugin] = nil
            guard state.phase == .ready,
                  state.inFlight.values.contains(where: { $0.plugin == plugin }),
                  let link = state.link
            else { return }

            state.isKilling = true
            state.outbox.append { link.kill() }
        }
        drain()
    }

    /// finish completes one dispatch with the host's answer. No answer means the connection broke
    /// before the host replied, which is the loss of that host.
    private func finish(
        _ id         : UInt64,
        of generation: UInt64,
        with result  : PluginExecutionResult?
    ) {
        guard let result else {
            lose(generation)
            return
        }

        state.withLock { state in
            if let dispatch = state.inFlight.removeValue(forKey: id) {
                state.outbox.append { dispatch.completion(result) }
            }
        }
        drain()
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
            self?.greet(generation, with: incarnation)
        }
    }

    private func greet(
        _ generation    : UInt64,
        with incarnation: PluginHostIncarnation?
    ) {
        guard incarnation != nil else {
            lose(generation)
            return
        }

        let now = clock()
        state.withLock { state in
            guard state.generation == generation, state.phase == .connecting, let link = state.link else { return }

            state.phase = .ready
            state.supervisor.launched(at: now)
            for (plugin, entryPoint) in state.plugins.sorted(by: { $0.key.rawValue < $1.key.rawValue }) {
                state.outbox.append { link.start(plugin, entryPoint: entryPoint) }
            }
            if let observer = state.observer {
                state.outbox.append { observer(.available) }
            }
        }
        drain()
    }

    /// lose ends one host. The engine hears that the host is unavailable before it hears about
    /// the dispatches the loss ended, so the plugins it primes again wait for the next host.
    private func lose(_ generation: UInt64) {
        let now = clock()
        state.withLock { state in
            guard state.generation == generation, state.phase == .connecting || state.phase == .ready else { return }

            let cause: PluginHostSupervisor.Loss = state.isKilling
                ? .killed
                : (state.inFlight.isEmpty ? .crashedIdle : .crashed)
            let outcome = state.isKilling
                ? PluginExecutionResult.lost
                : PluginExecutionResult(outcome: .failed, cpuTime: .zero)
            let delay      = state.supervisor.lost(cause, at: now)
            let dispatches = state.inFlight.values

            if let link = state.link {
                state.outbox.append { link.invalidate() }
            }
            if let observer = state.observer {
                state.outbox.append { observer(.unavailable) }
            }
            for dispatch in dispatches {
                state.outbox.append { dispatch.completion(outcome) }
            }
            if let delay {
                let retry: @Sendable () -> Void = { [weak self] in
                    self?.retry(generation)
                }
                state.outbox.append { [schedule] in schedule(delay, retry) }
            }

            state.inFlight.removeAll()
            state.link      = nil
            state.isKilling = false
            state.phase     = delay == nil ? .disconnected : .waiting
        }
        drain()
    }

    private func retry(_ generation: UInt64) {
        state.withLock { state in
            if state.generation == generation, state.phase == .waiting {
                state.phase = .disconnected
            }
        }

        connectIfNeeded()
    }

    /// drain runs the outbox in order, one call at a time, with the lock released. Only one thread
    /// drains at once; a call that queues more, or another thread that queues meanwhile, leaves
    /// them to the thread already draining, so the order the lock decided is the order of calls.
    private func drain() {
        let claimed = state.withLock { state in
            guard !state.isDraining else { return false }

            state.isDraining = true
            return true
        }
        guard claimed else { return }

        while let call = state.withLock({ state -> (@Sendable () -> Void)? in
            guard !state.outbox.isEmpty else {
                state.isDraining = false
                return nil
            }

            return state.outbox.removeFirst()
        }) {
            call()
        }
    }
}
