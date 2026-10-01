//
//  PluginHostListener.swift
//  CascadeKit
//

import Foundation

/// PluginHostListener accepts the connections to PluginHost. A service bundled in an app
/// answers only that app already; given a code signing requirement, the listener also demands
/// it of every peer, so nothing but Cascade reaches the plugins.
public final class PluginHostListener: NSObject, NSXPCListenerDelegate, Sendable {

    private let service    : PluginHostService
    private let requirement: String?

    public init(
        service    : PluginHostService,
        requirement: String?
    ) {
        self.service     = service
        self.requirement = requirement
    }

    public func listener(
        _ listener                          : NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        if let requirement {
            connection.setCodeSigningRequirement(requirement)
        }
        connection.exportedInterface = NSXPCInterface(with: PluginHostProtocol.self)
        connection.exportedObject    = service
        connection.resume()

        return true
    }
}
