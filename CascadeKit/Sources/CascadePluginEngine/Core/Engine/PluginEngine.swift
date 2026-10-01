//
//  PluginEngine.swift
//  CascadeKit
//

import CascadeContracts
import Dispatch
import Synchronization

/// PluginEngine is the kernel's imperative shell. Every call hops to the engine's serial queue,
/// so a caller, often the main thread, never waits on the kernel's lock. On that queue the
/// kernel decides under the lock, the lock is released, and only then are plugins, sources and
/// the sink called. One timer, rearmed from the kernel's `nextDelay` after every call, covers
/// the watchdogs, retries, held events and wakes; with nothing due it is disarmed, so an idle
/// engine never wakes the CPU.
public final class PluginEngine: Sendable {

    private let kernel  : Mutex<PluginKernel>
    private let queue   = DispatchQueue(label: "cascade.plugin-engine", qos: .userInitiated)
    private let timer   : any DispatchSourceTimer
    private let executor: any PluginExecutor
    private let sources : [String: any PluginEventSource]
    private let sink    : any PluginPublicationSink

    public init(
        executor  : any PluginExecutor,
        sources   : [String: any PluginEventSource],
        services  : Set<String> = [],
        components: Set<String> = [],
        sink      : any PluginPublicationSink,
        policy    : any PluginHealthPolicy = StandardHealthPolicy()
    ) {
        self.executor = executor
        self.sources  = sources
        self.sink     = sink
        kernel        = Mutex(
            PluginKernel(
                capabilities: PluginHostCapabilities(sources: Set(sources.keys), services: services, components: components),
                policy      : policy
            )
        )
        timer         = DispatchSource.makeTimerSource(queue: queue)

        timer.setEventHandler { [weak self] in
            self?.execute { kernel, now in kernel.tick(at: now) }
        }
        timer.activate()
    }

    deinit {
        timer.cancel()
    }

    public func register(
        _ manifest: PluginManifest,
        grants    : Set<String>
    ) {
        run { kernel, now in kernel.register(manifest, grants: grants, at: now) }
    }

    public func receive(_ event: PluginSourceEvent) {
        run { kernel, now in kernel.receive(event, at: now) }
    }

    public func setVisible(
        _ isVisible: Bool,
        for key    : PluginPublicationKey
    ) {
        run { kernel, now in kernel.setVisible(isVisible, for: key, at: now) }
    }

    public func submit(_ request: PluginActionRequest) {
        run { kernel, now in kernel.submit(request, at: now) }
    }

    public func revoke(
        _ permission: String,
        from plugin : PluginID
    ) {
        run { kernel, now in kernel.revoke(permission, from: plugin, at: now) }
    }

    public func grant(
        _ permission: String,
        to plugin   : PluginID
    ) {
        run { kernel, now in kernel.grant(permission, to: plugin, at: now) }
    }

    public func reenable(_ plugin: PluginID) {
        run { kernel, now in kernel.reenable(plugin, at: now) }
    }

    /// state reads a plugin's state after everything already queued. It waits for the engine's
    /// queue, so it is for tests and tools: never call it from the main thread or the sink.
    public func state(of plugin: PluginID) -> PluginState? {
        queue.sync {
            kernel.withLock { $0.state(of: plugin) }
        }
    }

    private func run(_ operation: @escaping @Sendable (inout PluginKernel, PluginInstant) -> [PluginEngineEffect]) {
        queue.async { [self] in
            execute(operation)
        }
    }

    /// execute runs one kernel operation under the lock, then performs its effects and rearms
    /// the timer with the lock released.
    private func execute(_ operation: (inout PluginKernel, PluginInstant) -> [PluginEngineEffect]) {
        let now              = PluginInstant.now()
        let (effects, delay) = kernel.withLock { kernel in
            let effects = operation(&kernel, now)
            return (effects, kernel.nextDelay(at: now))
        }

        for effect in effects {
            perform(effect)
        }
        rearm(after: delay)
    }

    private func perform(_ effect: PluginEngineEffect) {
        switch effect {
            case .start(let plugin, let entryPoint):
                executor.start(plugin, entryPoint: entryPoint)

            case .dispatch(let plugin, let event, let token):
                executor.dispatch(event, to: plugin) { [weak self] result in
                    self?.run { kernel, now in kernel.complete(plugin, token: token, result: result, at: now) }
                }

            case .stop(let plugin):
                executor.stop(plugin)

            case .startSource(let name):
                sources[name]?.start { [weak self] event in
                    self?.receive(event)
                }

            case .stopSource(let name):
                sources[name]?.stop()

            case .deliver(let changes):
                sink.deliver(changes)

            case .reject(let request):
                sink.reject(request)
        }
    }

    /// rearm points the one timer at the next due moment, or disarms it.
    private func rearm(after delay: Duration?) {
        guard let delay else {
            timer.schedule(deadline: .distantFuture)
            return
        }

        timer.schedule(
            deadline: .now() + delay / .seconds(1),
            leeway  : .milliseconds(10)
        )
    }
}
