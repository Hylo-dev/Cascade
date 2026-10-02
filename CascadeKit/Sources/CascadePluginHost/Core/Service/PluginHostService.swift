//
//  PluginHostService.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// PluginHostService is the object PluginHost exports. It decodes every event with the
/// contracts' validation, runs it on the plugin's own thread through the runner, and answers
/// with the output and the thread's CPU time. An event that is too large or does not decode is
/// answered with no output, as a throw would be. It also runs the catalog sources the kernel
/// leases and sends their states back to the connection that asked.
public final class PluginHostService: NSObject, PluginHostProtocol, Sendable {

    static let maximumEventBytes = 65_536

    private let runner : PluginRunner
    private let sources: PluginSourceRuntime

    public init(
        runner : PluginRunner,
        sources: PluginSourceRuntime = PluginSourceRuntime(sources: [:])
    ) {
        self.runner  = runner
        self.sources = sources
    }

    public func hello(reply: @escaping @Sendable (Int32) -> Void) {
        reply(getpid())
    }

    public func start(
        plugin    : String,
        entryPoint: String
    ) {
        guard let plugin = PluginID(rawValue: plugin) else { return }

        runner.start(plugin, entryPoint: entryPoint)
    }

    public func handle(
        plugin: String,
        event : Data,
        reply : @escaping @Sendable (Data?, UInt64) -> Void
    ) {
        guard let plugin = PluginID(rawValue: plugin),
              event.count <= Self.maximumEventBytes,
              let decoded = try? JSONDecoder().decode(PluginEvent.self, from: event)
        else {
            reply(nil, 0)
            return
        }

        runner.run(decoded, for: plugin) { run in
            reply(run.output.flatMap { try? JSONEncoder().encode($0) }, UInt64(max(0, run.cpuTime / .nanoseconds(1))))
        }
    }

    public func startSource(name: String) {
        guard let client = NSXPCConnection.current()?.remoteObjectProxy as? any PluginHostClientProtocol else { return }

        let proxy = ClientProxy(client: client)
        sources.start(name) { event in
            if let data = try? JSONEncoder().encode(event) {
                proxy.client.sourceChanged(event: data)
            }
        }
    }

    public func stopSource(name: String) {
        sources.stop(name)
    }

    /// stopSources stops every source, when the connection that started them ends.
    public func stopSources() {
        sources.stopAll()
    }

    /// ClientProxy carries the connection's proxy into the sources' callbacks. An XPC proxy may
    /// be messaged from any thread, as its documentation states, but the SDK does not mark it
    /// Sendable.
    private struct ClientProxy: @unchecked Sendable {

        let client: any PluginHostClientProtocol
    }
}
