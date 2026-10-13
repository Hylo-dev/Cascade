//
//  AudioHostConnecting.swift
//  Cascade
//

import CascadeContracts

/// AudioHostConnecting is the XPC seam between the per-app audio service and AudioHost. It is a
/// protocol so the service is tested against a fake connection, with no process behind it.
///
/// Every call happens on the service's serial queue, never on the main thread, and every
/// callback arrives on whatever thread XPC picks. A conformer is therefore `nonisolated`, and so
/// are the closures it is given, or a main-actor callback running off main would trap.
nonisolated protocol AudioHostConnecting: AnyObject, Sendable {

    /// connect opens a fresh connection and returns whether it could. `onSnapshot` receives each
    /// state AudioHost publishes, already validated; `onLoss` runs once when the link breaks
    /// without `disconnect` having asked for it.
    func connect(
        onSnapshot: @escaping @Sendable (AudioHostSnapshot) -> Void,
        onLoss    : @escaping @Sendable () -> Void
    ) -> Bool

    /// hello replies with AudioHost's PID once the handshake is checked, or nil when the link
    /// broke or the peer was not the process it claimed to be.
    func hello(_ reply: @escaping @Sendable (Int32?) -> Void)

    /// send delivers one command and replies whether AudioHost accepted it, or nil when the link
    /// broke before it answered.
    func send(
        _ command: AudioHostCommand,
        reply    : @escaping @Sendable (Bool?) -> Void
    )

    /// footprint is AudioHost's physical footprint in bytes, or nil when it is not known.
    func footprint() -> UInt64?

    /// kill ends the AudioHost process this connection reached, if it is still that process.
    func kill()

    /// disconnect closes the connection without reporting a loss.
    func disconnect()
}
