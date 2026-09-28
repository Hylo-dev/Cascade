//
//  IOBluetoothConnectionCallback.swift
//  Cascade
//

/// IOBluetoothConnectionCallback carries a framework callback across to the
/// main actor without retaining or sending an `IOBluetoothDevice`.
nonisolated enum IOBluetoothConnectionCallback: Sendable {

    case connected(
        identity: BluetoothConnectionCallbackIdentity,
        device  : BluetoothConnectedDevice
    )

    case disconnected(
        identity: BluetoothConnectionCallbackIdentity,
        deviceID: String
    )
}
