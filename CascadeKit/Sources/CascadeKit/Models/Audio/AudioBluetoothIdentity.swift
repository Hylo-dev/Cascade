//
//  AudioBluetoothIdentity.swift
//  CascadeKit
//

import CascadeContracts

/// AudioBluetoothIdentity is what the Bluetooth source verified about an output device, enough
/// for the widget to draw the product itself instead of a generic headphones symbol.
nonisolated public struct AudioBluetoothIdentity: Equatable, Hashable, Sendable {

    public let model    : PluginBluetoothDeviceModel
    public let productID: UInt16?
    public let colorID  : UInt8?

    public init(
        model    : PluginBluetoothDeviceModel,
        productID: UInt16?,
        colorID  : UInt8?
    ) {
        self.model     = model
        self.productID = productID
        self.colorID   = colorID
    }
}
