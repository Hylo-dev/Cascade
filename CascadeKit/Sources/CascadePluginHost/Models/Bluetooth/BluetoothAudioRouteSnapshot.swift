//
//  BluetoothAudioRouteSnapshot.swift
//  CascadeKit
//

import CascadeContracts
import CoreAudio
import Foundation

/// BluetoothAudioRouteSnapshot is a small value copied from the current CoreAudio output, never an
/// IOBluetooth object.
struct BluetoothAudioRouteSnapshot: Equatable, Sendable {

    let uid          : String
    let name         : String
    let transportType: UInt32

    var bluetoothDevice: BluetoothConnectedDevice? {
        guard transportType == kAudioDeviceTransportTypeBluetooth
                || transportType == kAudioDeviceTransportTypeBluetoothLE,
              let address = PluginBluetoothAddress.outputAddress(fromUID: uid)
        else { return nil }

        return BluetoothConnectedDevice(
            deviceID  : address,
            name      : name,
            symbolName: "headphones"
        )
    }
}
