//
//  AudioOutputDevice.swift
//  CascadeKit
//

import CascadeContracts

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
