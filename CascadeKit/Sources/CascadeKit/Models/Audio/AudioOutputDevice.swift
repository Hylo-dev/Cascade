//
//  AudioOutputDevice.swift
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

/// AudioOutputDevice is one output the system can play to. It is a plain value, built on the
/// audio service's own queue and handed to the main actor whole, so it carries no HAL handle: the
/// `uid` is the stable identity, and the `transportType` is the raw `kAudioDeviceTransportType*`
/// four-char code, kept as a number so this module never imports CoreAudio.
nonisolated public struct AudioOutputDevice: Equatable, Hashable, Sendable {

    public let uid          : String
    public let name         : String
    public let transportType: UInt32
    public let bluetooth    : AudioBluetoothIdentity?

    public init(
        uid          : String,
        name         : String,
        transportType: UInt32,
        bluetooth    : AudioBluetoothIdentity?
    ) {
        self.uid           = uid
        self.name          = name
        self.transportType = transportType
        self.bluetooth     = bluetooth
    }
}
