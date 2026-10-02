//
//  PluginTransport.swift
//  CascadeKit
//

import CascadeContracts

/// PluginTransport reaches a PluginHost process: over XPC in production, in memory in tests.
public protocol PluginTransport: Sendable {

    /// connect opens a link to a host. `onLoss` runs on any thread when the link breaks: the
    /// host died or was killed, or the connection was invalidated. `onSourceEvent` receives the
    /// states of the sources started on this link, on any thread.
    func connect(
        onLoss       : @escaping @Sendable () -> Void,
        onSourceEvent: @escaping @Sendable (PluginSourceEvent) -> Void
    ) -> any PluginHostLink
}
