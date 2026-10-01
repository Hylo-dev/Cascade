//
//  XPCPluginTransport.swift
//  CascadeKit
//

import Foundation

/// XPCPluginTransport reaches PluginHost over XPC: by its service name inside Cascade's bundle,
/// or through an anonymous listener's endpoint in tests. Every connection is new, so a lost host
/// is met again with a fresh handshake.
public struct XPCPluginTransport: PluginTransport {

    private let open       : @Sendable () -> NSXPCConnection
    private let requirement: String?

    public init(
        serviceName: String,
        requirement: String?
    ) {
        open             = { NSXPCConnection(serviceName: serviceName) }
        self.requirement = requirement
    }

    init(endpoint: NSXPCListenerEndpoint) {
        open        = { NSXPCConnection(listenerEndpoint: endpoint) }
        requirement = nil
    }

    public func connect(onLoss: @escaping @Sendable () -> Void) -> any PluginHostLink {
        XPCPluginHostLink(connection: open(), requirement: requirement, onLoss: onLoss)
    }
}
