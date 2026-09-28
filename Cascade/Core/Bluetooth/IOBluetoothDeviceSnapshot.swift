//
//  IOBluetoothDeviceSnapshot.swift
//  Cascade
//

import AppKit
import IOBluetooth
import os

/// IOBluetoothDeviceSnapshot copies the small public metadata set used by the
/// activity before the framework-owned device leaves its callback queue.
nonisolated enum IOBluetoothDeviceSnapshot {

    static func make(
        from device: IOBluetoothDevice
    ) -> BluetoothConnectedDevice? {

        guard let deviceID = stableIdentifier(for: device) else { return nil }
        return BluetoothConnectedDevice(
            deviceID   : deviceID,
            name       : device.name ?? device.nameOrAddress ?? "Bluetooth Device",
            symbolName : symbolName(for: device)
        )
    }

    /// connectedDevices combines the framework's cached paired and recent
    /// lists because either list alone can omit a valid Classic device. Every
    /// call is a synchronous bluetoothd round trip, so it runs off the main
    /// actor; these APIs read existing records and never start discovery.
    static func connectedDevices() -> [IOBluetoothDevice] {

        let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let recentDevices = IOBluetoothDevice.recentDevices(0) as? [IOBluetoothDevice] ?? []
        var devicesByID   : [String: IOBluetoothDevice] = [:]

        for device in pairedDevices + recentDevices where device.isConnected() {
            guard let deviceID = stableIdentifier(for: device) else { continue }
            devicesByID[deviceID] = device
        }

        return Array(devicesByID.values)
    }

    static func stableIdentifier(
        for device: IOBluetoothDevice
    ) -> String? {
        // IOBluetooth declares this as an IUO, but disconnect can clear its cache
        // before the callback arrives. A missing identity must never be force-unwrapped.
        guard let address = device.addressString,
              BluetoothMetadataParser.normalizedAddress(address) != nil else { return nil }
        return address.uppercased()
    }

    /// symbolName maps the public Bluetooth class-of-device category to a
    /// conservative SF Symbol without claiming a model the framework omitted.
    private static func symbolName(
        for device: IOBluetoothDevice
    ) -> String {

        switch device.deviceClassMajor {
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio):
            switch device.deviceClassMinor {
            case BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioHeadset),
                 BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioHandsFree),
                 BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioHeadphones):
                return "headphones"
            default:
                return "speaker.wave.2"
            }
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorComputer):
            return "desktopcomputer"
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPhone):
            return "smartphone"
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPeripheral):
            let peripheralKind = device.deviceClassMinor & 0x30

            if peripheralKind == kBluetoothDeviceClassMinorPeripheral1Keyboard {
                return "keyboard"
            }

            if peripheralKind == kBluetoothDeviceClassMinorPeripheral1Pointing {
                return "computermouse"
            }

            return "gamecontroller"
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorImaging):
            return "camera"
        default:
            return "antenna.radiowaves.left.and.right"
        }
    }
}
