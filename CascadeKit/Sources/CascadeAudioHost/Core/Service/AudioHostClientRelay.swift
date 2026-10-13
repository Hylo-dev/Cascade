//
//  AudioHostClientRelay.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import os
import Synchronization

/// AudioHostClientRelay carries the service's snapshots to whichever mixer connection is
/// current. The service is created once and outlives every connection, while the XPC proxy to
/// the mixer belongs to one connection, so something has to hold the current proxy: this.
///
/// A new connection replaces the previous one, and a connection that ends only detaches itself
/// (by the id `attach` gave it), so a late invalidation of an old connection can never unhook the
/// new one. Nothing is called under the lock: the proxy is copied out, the lock released, then
/// the message sent.
public final class AudioHostClientRelay: Sendable {

    private let logger  = Logger(subsystem: "hylo.Cascade", category: "AudioHostRelay")
    private let current = Mutex<Attachment?>(nil)
    private let counter = Mutex<UInt64>(0)

    public init() {}

    /// attach makes `client` the receiver of every snapshot from now on and returns the id that
    /// `detach` needs.
    public func attach(_ client: any AudioHostClientProtocol) -> UInt64 {
        let identifier = counter.withLock { value -> UInt64 in
            value += 1

            return value
        }

        current.withLock { $0 = Attachment(identifier: identifier, client: client) }

        return identifier
    }

    /// detach drops the client `identifier` named, and does nothing if a newer one replaced it.
    public func detach(_ identifier: UInt64) {
        current.withLock { attachment in
            if attachment?.identifier == identifier { attachment = nil }
        }
    }

    /// publish encodes the snapshot through the wire and hands it to the current client, if any.
    public func publish(_ snapshot: AudioHostSnapshot) {
        guard let client = current.withLock({ $0?.client }) else { return }

        do {
            client.publish(try AudioHostWire.encode(snapshot))
        } catch {
            logger.error("Audio snapshot not published: \(String(describing: error), privacy: .public)")
        }
    }

    /// Attachment pairs a client with its id. An XPC proxy may be messaged from any thread, as
    /// its documentation states, but the protocol does not mark it Sendable.
    private struct Attachment: @unchecked Sendable {

        let identifier : UInt64
        let client     : any AudioHostClientProtocol
    }
}
