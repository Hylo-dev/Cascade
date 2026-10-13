//
//  AudioHostClient.swift
//  Cascade
//

import CascadeContracts
import CascadePluginEngine
import CascadePluginHost
import Foundation
import Synchronization

/// AudioHostClient reaches AudioHost over XPC, by its service name inside Cascade's bundle. It is
/// the real `AudioHostConnecting`: one `connect` makes one `NSXPCConnection` and every later
/// connection is new, so a lost AudioHost is met again with a fresh handshake.
///
/// Each call goes through a proxy with its own error handler, so every reply runs exactly once:
/// with AudioHost's answer, or with nil when the connection broke first. The handshake checks the
/// PID AudioHost reports against the connection's peer and records the incarnation that `kill`
/// and `footprint` act on, the same `PluginHostIncarnation` PluginHost uses: it signals only
/// while the live process at the recorded PID still is the one that answered.
///
/// A requirement is demanded of the peer only when Cascade is signed by a team; an ad hoc build
/// relies on the system rule that an XPC service bundled in an app answers only that app. Reading
/// the signature touches the disk, so `connect` does it on the service's queue, which is rare: a
/// reconnection waits at least a second.
nonisolated final class AudioHostClient: AudioHostConnecting, Sendable {

    private let serviceName: String
    private let current    = Mutex<Link?>(nil)

    init(serviceName: String = (Bundle.main.bundleIdentifier ?? "hylo.Cascade") + ".AudioHost") {
        self.serviceName = serviceName
    }

    func connect(
        onSnapshot: @escaping @Sendable (AudioHostSnapshot) -> Void,
        onLoss    : @escaping @Sendable () -> Void
    ) -> Bool {
        let link = Link(
            connection : NSXPCConnection(serviceName: serviceName),
            requirement: PluginHostSigning.requirement(identifier: serviceName, team: PluginHostSigning.currentTeam),
            onSnapshot : onSnapshot,
            onLoss     : onLoss
        )

        let replaced = current.withLock { current in
            defer { current = link }

            return current
        }
        replaced?.close()

        return true
    }

    func hello(_ reply: @escaping @Sendable (Int32?) -> Void) {
        guard let link = current.withLock({ $0 }) else {
            reply(nil)
            return
        }

        link.hello(reply)
    }

    func send(
        _ command: AudioHostCommand,
        reply    : @escaping @Sendable (Bool?) -> Void
    ) {
        guard let link = current.withLock({ $0 }) else {
            reply(nil)
            return
        }

        link.send(command, reply: reply)
    }

    func footprint() -> UInt64? {
        current.withLock { $0 }?.footprint()
    }

    func kill() {
        current.withLock { $0 }?.kill()
    }

    func disconnect() {
        let closed = current.withLock { current in
            defer { current = nil }

            return current
        }
        closed?.close()
    }

    /// Link is one connection to AudioHost and the object it exports back. A link that was closed
    /// on purpose reports no loss, so a stale connection cannot cry for a newer one.
    nonisolated private final class Link: NSObject, AudioHostClientProtocol, Sendable {

        // NSXPCConnection is safe to message from any thread, as its documentation states, but
        // the SDK does not mark it Sendable; the link never mutates it after init but for
        // invalidate().
        nonisolated(unsafe) private let connection: NSXPCConnection

        private let onSnapshot : @Sendable (AudioHostSnapshot) -> Void
        private let onLoss     : @Sendable () -> Void
        private let incarnation = Mutex<PluginHostIncarnation?>(nil)
        private let isSettled   = Mutex(false)

        init(
            connection : NSXPCConnection,
            requirement: String?,
            onSnapshot : @escaping @Sendable (AudioHostSnapshot) -> Void,
            onLoss     : @escaping @Sendable () -> Void
        ) {
            self.connection = connection
            self.onSnapshot = onSnapshot
            self.onLoss     = onLoss

            super.init()

            connection.remoteObjectInterface = NSXPCInterface(with: AudioHostProtocol.self)
            connection.exportedInterface     = NSXPCInterface(with: AudioHostClientProtocol.self)
            connection.exportedObject        = self
            if let requirement {
                connection.setCodeSigningRequirement(requirement)
            }
            connection.interruptionHandler = { [weak self] in self?.lose() }
            connection.invalidationHandler = { [weak self] in self?.lose() }
            connection.resume()
        }

        func publish(_ snapshot: Data) {
            guard let decoded = try? AudioHostWire.decode(AudioHostSnapshot.self, from: snapshot) else { return }

            onSnapshot(decoded)
        }

        func hello(_ reply: @escaping @Sendable (Int32?) -> Void) {
            proxy { reply(nil) }?.hello { [self] pid in
                guard pid == connection.processIdentifier, let live = PluginHostIncarnation(pid: pid) else {
                    reply(nil)
                    return
                }

                incarnation.withLock { $0 = live }
                reply(pid)
            }
        }

        func send(
            _ command: AudioHostCommand,
            reply    : @escaping @Sendable (Bool?) -> Void
        ) {
            guard let data = try? AudioHostWire.encode(command) else {
                reply(false)
                return
            }

            proxy { reply(nil) }?.send(data) { accepted in reply(accepted) }
        }

        func footprint() -> UInt64? {
            incarnation.withLock { $0 }?.footprint()
        }

        func kill() {
            _ = incarnation.withLock { $0 }?.kill()
        }

        /// close invalidates the connection and silences the link, so the invalidation it
        /// causes is not mistaken for a loss.
        func close() {
            isSettled.withLock { $0 = true }
            connection.invalidate()
        }

        private func lose() {
            let isFirst = isSettled.withLock { isSettled in
                defer { isSettled = true }

                return !isSettled
            }

            if isFirst {
                onLoss()
            }
        }

        /// proxy returns AudioHost's proxy for one call, whose error handler runs `failed` when
        /// the connection breaks before the reply. A proxy of another type cannot happen with
        /// this interface; if it did, the call fails the same way.
        private func proxy(_ failed: @escaping @Sendable () -> Void) -> (any AudioHostProtocol)? {
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in failed() }) as? any AudioHostProtocol else {
                failed()
                return nil
            }

            return proxy
        }
    }
}
