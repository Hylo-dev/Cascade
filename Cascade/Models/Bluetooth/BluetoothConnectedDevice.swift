//
//  BluetoothConnectedDevice.swift
//  Cascade
//

import Foundation

/// BluetoothConnectedDevice is the framework-free snapshot retained while a
/// Bluetooth device is connected.
///
/// Keeping this value separate from `IOBluetoothDevice` makes transition
/// handling deterministic and preserves the last useful name and icon when a
/// disconnect callback arrives after the framework has discarded metadata.
nonisolated struct BluetoothConnectedDevice: Equatable, Sendable {

    let deviceID  : String
    let name      : String
    let symbolName: String
    let battery   : BluetoothBatterySnapshot?
    let model     : BluetoothDeviceModel
    let productID : UInt16?
    let colorID   : UInt8?

    init(
        deviceID  : String,
        name      : String,
        symbolName: String,
        battery   : BluetoothBatterySnapshot? = nil,
        model     : BluetoothDeviceModel = .generic,
        productID : UInt16? = nil,
        colorID   : UInt8? = nil
    ) {
        self.deviceID   = deviceID
        self.name       = name
        self.symbolName = symbolName
        self.battery    = battery
        self.model      = model
        self.productID  = productID
        self.colorID    = colorID
    }

    /// enriched keeps known fields when sparse duplicate callbacks omit them.
    func enriched(with metadata: BluetoothDeviceMetadata) -> BluetoothConnectedDevice {
        BluetoothConnectedDevice(
            deviceID  : deviceID,
            name      : name,
            symbolName: symbolName,
            battery   : metadata.battery?.fillingMissing(from: battery) ?? battery,
            model     : metadata.model == .generic ? model : metadata.model,
            productID : metadata.productID ?? productID,
            colorID   : metadata.colorID ?? colorID
        )
    }
}
