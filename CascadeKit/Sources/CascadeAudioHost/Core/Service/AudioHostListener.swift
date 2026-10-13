//
//  AudioHostListener.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// AudioHostListener accepts the connections to AudioHost. A service bundled in an app answers
/// only that app already; given a code signing requirement, the listener also demands it of every
/// peer, so nothing but Cascade can steer another app's audio. The requirement is built by the
/// composition root (`PluginHostSigning.requirement`), so this target stays free of PluginHost.
///
/// One mixer is connected at a time: a new connection becomes the relay's client and is sent the
/// current state at once, because a snapshot is published only when something changes and a
/// mixer that connects to a quiet AudioHost would otherwise wait for one.
public final class AudioHostListener: NSObject, NSXPCListenerDelegate, Sendable {

    private let service     : AudioHostService
    private let relay       : AudioHostClientRelay
    private let requirement : String?

    public init(
        service     : AudioHostService,
        relay       : AudioHostClientRelay,
        requirement : String?
    ) {
        self.service     = service
        self.relay       = relay
        self.requirement = requirement
    }

    public func listener(
        _ listener                          : NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        if let requirement {
            connection.setCodeSigningRequirement(requirement)
        }

        connection.exportedInterface     = NSXPCInterface(with: AudioHostProtocol.self)
        connection.exportedObject        = service
        connection.remoteObjectInterface = NSXPCInterface(with: AudioHostClientProtocol.self)

        if let client = connection.remoteObjectProxy as? any AudioHostClientProtocol {
            let identifier = relay.attach(client)

            connection.invalidationHandler = { [relay] in relay.detach(identifier) }
        }

        connection.resume()
        service.republish()

        return true
    }
}
