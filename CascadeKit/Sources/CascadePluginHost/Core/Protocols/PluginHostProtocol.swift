//
//  PluginHostProtocol.swift
//  CascadeKit
//

import Foundation

/// PluginHostProtocol is the whole XPC surface of PluginHost: a handshake that names the
/// process, loading a plugin, one event at a time per plugin, and the catalog sources the kernel
/// leases. Events and outputs travel as
/// JSON, the contracts' own wire form, so each side validates what it decodes.
@objc
public protocol PluginHostProtocol {

    /// hello replies with the host's PID, which the kernel checks against the connection's peer.
    func hello(reply: @escaping @Sendable (Int32) -> Void)

    func start(
        plugin    : String,
        entryPoint: String
    )

    /// startSource starts a catalog source, whose states come back through the connection's
    /// `PluginHostClientProtocol`; starting a running one restarts it, so it emits its state again.
    func startSource(name: String)

    func stopSource(name: String)

    /// handle runs one event and replies with the output, or no output when the plugin threw or
    /// the event was invalid, and the CPU time the plugin's thread spent, in nanoseconds.
    func handle(
        plugin: String,
        event : Data,
        reply : @escaping @Sendable (Data?, UInt64) -> Void
    )
}
