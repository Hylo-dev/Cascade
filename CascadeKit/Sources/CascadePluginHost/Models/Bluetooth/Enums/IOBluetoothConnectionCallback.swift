//
//  IOBluetoothConnectionCallback.swift
//  CascadeKit
//

/// IOBluetoothConnectionCallback carries a framework callback across to the
/// Bluetooth source's queue without retaining or sending an `IOBluetoothDevice`.
enum IOBluetoothConnectionCallback: Sendable {

    case connected(
        identity: BluetoothConnectionCallbackIdentity,
        device  : BluetoothConnectedDevice
    )

    case disconnected(
        identity: BluetoothConnectionCallbackIdentity,
        deviceID: String
    )
}
