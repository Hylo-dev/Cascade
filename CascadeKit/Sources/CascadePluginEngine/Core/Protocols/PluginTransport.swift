//
//  PluginTransport.swift
//  CascadeKit
//

/// PluginTransport reaches a PluginHost process: over XPC in production, in memory in tests.
public protocol PluginTransport: Sendable {

    /// connect opens a link to a host. `onLoss` runs on any thread when the link breaks: the
    /// host died or was killed, or the connection was invalidated.
    func connect(onLoss: @escaping @Sendable () -> Void) -> any PluginHostLink
}
