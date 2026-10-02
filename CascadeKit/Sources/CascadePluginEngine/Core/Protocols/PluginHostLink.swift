//
//  PluginHostLink.swift
//  CascadeKit
//

import CascadeContracts

/// PluginHostLink is one connection to one PluginHost incarnation. Every reply runs once, on any
/// thread; a reply of nil means the link broke before the host answered.
public protocol PluginHostLink: AnyObject, Sendable {

    /// hello completes the handshake with the incarnation the kernel may later kill, or nil when
    /// the host could not show which process it is.
    func hello(_ reply: @escaping @Sendable (PluginHostIncarnation?) -> Void)

    func start(
        _ plugin  : PluginID,
        entryPoint: String
    )

    func handle(
        _ event   : PluginEvent,
        for plugin: PluginID,
        reply     : @escaping @Sendable (PluginExecutionResult?) -> Void
    )

    /// startSource runs a catalog source in this host; its states arrive through the transport's
    /// `onSourceEvent`.
    func startSource(_ name: String)

    func stopSource(_ name: String)

    /// footprint is the memory the incarnation of the handshake uses, in bytes, or nil before the
    /// handshake or once it is gone.
    func footprint() -> UInt64?

    /// kill sends SIGKILL to the incarnation of the handshake, and only to it.
    func kill()

    func invalidate()
}
