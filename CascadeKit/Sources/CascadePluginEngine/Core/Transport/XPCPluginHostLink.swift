//
//  XPCPluginHostLink.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginHost
import Foundation
import Synchronization

/// XPCPluginHostLink is one NSXPCConnection to PluginHost. Each call goes through a proxy with
/// its own error handler, so every reply runs exactly once: with the host's answer, or with nil
/// when the connection broke first. The handshake checks the PID the host reports against the
/// connection's peer and records the incarnation that `kill` may signal; the loss is reported
/// once, whether XPC calls it an interruption or an invalidation.
final class XPCPluginHostLink: PluginHostLink {

    // NSXPCConnection is safe to message from any thread, as its documentation states, but the
    // SDK does not mark it Sendable; the link never mutates it after init but for invalidate().
    nonisolated(unsafe) private let connection: NSXPCConnection

    private let onLoss     : @Sendable () -> Void
    private let incarnation = Mutex<PluginHostIncarnation?>(nil)
    private let isLost      = Mutex(false)

    init(
        connection : NSXPCConnection,
        requirement: String?,
        onLoss     : @escaping @Sendable () -> Void
    ) {
        self.connection = connection
        self.onLoss     = onLoss

        connection.remoteObjectInterface = NSXPCInterface(with: PluginHostProtocol.self)
        if let requirement {
            connection.setCodeSigningRequirement(requirement)
        }
        connection.interruptionHandler = { [weak self] in self?.lose() }
        connection.invalidationHandler = { [weak self] in self?.lose() }
        connection.resume()
    }

    func hello(_ reply: @escaping @Sendable (PluginHostIncarnation?) -> Void) {
        proxy { reply(nil) }?.hello { [self] pid in
            guard pid == connection.processIdentifier, let live = PluginHostIncarnation(pid: pid) else {
                reply(nil)
                return
            }

            incarnation.withLock { $0 = live }
            reply(live)
        }
    }

    func start(
        _ plugin  : PluginID,
        entryPoint: String
    ) {
        proxy {}?.start(plugin: plugin.rawValue, entryPoint: entryPoint)
    }

    func handle(
        _ event   : PluginEvent,
        for plugin: PluginID,
        reply     : @escaping @Sendable (PluginExecutionResult?) -> Void
    ) {
        guard let data = try? JSONEncoder().encode(event) else {
            reply(PluginExecutionResult(outcome: .failed, cpuTime: .zero))
            return
        }

        proxy { reply(nil) }?.handle(plugin: plugin.rawValue, event: data) { output, nanoseconds in
            let decoded = output.flatMap { try? JSONDecoder().decode(PluginOutput.self, from: $0) }
            reply(PluginExecutionResult(output: decoded, cpuTime: .nanoseconds(Int64(clamping: nanoseconds))))
        }
    }

    func kill() {
        _ = incarnation.withLock { $0 }?.kill()
    }

    func invalidate() {
        connection.invalidate()
    }

    private func lose() {
        let isFirst = isLost.withLock { isLost in
            defer { isLost = true }

            return !isLost
        }

        if isFirst {
            onLoss()
        }
    }

    /// proxy returns the host's proxy for one call, whose error handler runs `failed` when the
    /// connection breaks before the reply. A proxy of another type cannot happen with this
    /// interface; if it did, the call fails the same way.
    private func proxy(_ failed: @escaping @Sendable () -> Void) -> (any PluginHostProtocol)? {
        guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in failed() }) as? any PluginHostProtocol else {
            failed()
            return nil
        }

        return proxy
    }
}
