//
//  BluetoothDeviceMetadata.swift
//  CascadeKit
//

import CascadeContracts

/// BluetoothDeviceMetadata is the Sendable result of one read-only system snapshot.
struct BluetoothDeviceMetadata: Equatable, Sendable {

    let battery  : BluetoothBatterySnapshot?
    let model    : PluginBluetoothDeviceModel
    let productID: UInt16?
    let colorID  : UInt8?

    init(
        battery  : BluetoothBatterySnapshot? = nil,
        model    : PluginBluetoothDeviceModel = .generic,
        productID: UInt16? = nil,
        colorID  : UInt8? = nil
    ) {
        self.battery   = battery
        self.model     = model
        self.productID = productID
        self.colorID   = colorID
    }

    /// needsRetry permits one delayed sample when connection metadata has not arrived.
    var needsRetry: Bool {
        guard battery?.level != nil else { return true }

        if model == .airPods || model == .airPodsPro {
            return battery?.left == nil || battery?.right == nil
        }
        return false
    }
}
