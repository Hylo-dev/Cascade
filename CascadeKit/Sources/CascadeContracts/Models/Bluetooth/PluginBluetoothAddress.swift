//
//  PluginBluetoothAddress.swift
//  CascadeKit
//

import Foundation

/// PluginBluetoothAddress reads a Bluetooth device address out of a CoreAudio output UID. It
/// lives in the contracts because both sides of the XPC line need the same answer: PluginHost
/// to name the connected output, and the app to match an output of the mixer to that device.
public enum PluginBluetoothAddress {

    /// outputAddress accepts only the exact output UID shape verified on the
    /// local AirPods and in Chromium's GetRelatedBluetoothDeviceIDs. Other HAL
    /// formats stay unknown: names, substrings and input UIDs cannot identify a
    /// connected output.
    public static func outputAddress(fromUID uid: String) -> String? {
        let suffix = ":output"
        guard uid.hasSuffix(suffix) else { return nil }

        let address = String(uid.dropLast(suffix.count)).uppercased()
        let groups  = address.split(separator: "-", omittingEmptySubsequences: false)

        guard groups.count == 6,
              groups.allSatisfy({ group in
                  group.utf8.count == 2 && group.utf8.allSatisfy { byte in
                      (48...57).contains(byte) || (65...70).contains(byte)
                  }
              })
        else { return nil }

        return address
    }
}
