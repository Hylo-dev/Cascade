//
//  BluetoothAudioRouteSnapshot.swift
//  Cascade
//

import CoreAudio
import Foundation

/// A small value copied from the current CoreAudio output, never an IOBluetooth object.
nonisolated struct BluetoothAudioRouteSnapshot: Equatable, Sendable {
    let uid: String
    let name: String
    let transportType: UInt32

    var bluetoothDevice: BluetoothConnectedDevice? {
        guard transportType == kAudioDeviceTransportTypeBluetooth
                || transportType == kAudioDeviceTransportTypeBluetoothLE,
              let address = Self.bluetoothAddress(for: uid) else { return nil }
        return BluetoothConnectedDevice(deviceID: address, name: name, symbolName: "headphones")
    }

    /// This exact output UID shape was verified on the local AirPods and in
    /// Chromium's GetRelatedBluetoothDeviceIDs. Other HAL formats stay unknown:
    /// names, substrings and input UIDs cannot identify a connected output.
    static func bluetoothAddress(for uid: String) -> String? {
        let suffix = ":output"
        guard uid.hasSuffix(suffix) else { return nil }
        let address = String(uid.dropLast(suffix.count)).uppercased()
        let groups = address.split(separator: "-", omittingEmptySubsequences: false)
        guard groups.count == 6, groups.allSatisfy({ group in
            group.utf8.count == 2 && group.utf8.allSatisfy {
                (48...57).contains($0) || (65...70).contains($0)
            }
        }) else { return nil }
        return address
    }
}
