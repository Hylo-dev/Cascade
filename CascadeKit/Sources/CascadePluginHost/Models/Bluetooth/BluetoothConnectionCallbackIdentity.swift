//
//  BluetoothConnectionCallbackIdentity.swift
//  CascadeKit
//

/// BluetoothConnectionCallbackIdentity identifies both a monitoring session
/// and the silent baseline within that session which accepted a callback.
struct BluetoothConnectionCallbackIdentity: Equatable, Sendable {

    let sessionID    : UInt64
    let baselineEpoch: UInt64
}
