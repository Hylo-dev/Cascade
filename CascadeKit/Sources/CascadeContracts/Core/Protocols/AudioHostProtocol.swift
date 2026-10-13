//
//  AudioHostProtocol.swift
//  CascadeKit
//

import Foundation

/// AudioHostProtocol is the whole XPC surface of AudioHost, the service that taps and steers
/// other apps' audio: a handshake that names the process, and one command channel. Commands
/// travel as JSON, the contracts' own wire form (`AudioHostWire`), so AudioHost validates
/// everything it decodes and a malformed message costs a `false` reply, never a crash.
@objc
public protocol AudioHostProtocol {

    /// hello replies with AudioHost's PID, which the mixer checks against the connection's peer.
    func hello(reply: @escaping @Sendable (Int32) -> Void)

    /// send applies one JSON `AudioHostCommand` and replies whether it was valid and accepted.
    /// Enforcement is asynchronous: the outcome comes back as a published snapshot.
    func send(
        _ command: Data,
        reply    : @escaping @Sendable (Bool) -> Void
    )
}
