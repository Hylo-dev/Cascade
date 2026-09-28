//
//  BluetoothConnectionCallbackIdentity.swift
//  Cascade
//

/// BluetoothConnectionCallbackIdentity identifies both a monitoring session
/// and the silent baseline within that session which accepted a callback.
nonisolated struct BluetoothConnectionCallbackIdentity: Equatable, Sendable {

    let sessionID    : UInt64
    let baselineEpoch: UInt64
}
