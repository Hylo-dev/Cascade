//
//  BluetoothConnectionEvent.swift
//  Cascade
//

/// BluetoothConnectionEvent describes one real device connection transition.
///
/// The model contains presentation-ready identity and naming, but no framework
/// objects. This keeps the event immutable and safe to carry through an
/// `AsyncStream` without retaining an IOBluetooth device. productID preserves
/// the exact Apple hardware generation when verified by its vendor identity;
/// it never substitutes a representative ID inferred from the display name.
nonisolated struct BluetoothConnectionEvent: Equatable, Sendable {

    enum Kind: Equatable, Sendable {

        case connection
        case audioRoute
    }

    let deviceID   : String
    let name       : String
    let symbolName : String
    let isConnected: Bool
    let battery    : BluetoothBatterySnapshot?
    let model      : BluetoothDeviceModel
    let productID  : UInt16?
    let colorID    : UInt8?
    let eventID    : UInt64
    let revision   : UInt64
    let kind       : Kind

    init(
        deviceID   : String,
        name       : String,
        symbolName : String,
        isConnected: Bool,
        battery    : BluetoothBatterySnapshot? = nil,
        model      : BluetoothDeviceModel = .generic,
        productID  : UInt16? = nil,
        colorID    : UInt8? = nil,
        eventID    : UInt64 = 0,
        revision   : UInt64 = 0,
        kind       : Kind = .connection
    ) {
        self.deviceID    = deviceID
        self.name        = name
        self.symbolName  = symbolName
        self.isConnected = isConnected
        self.battery     = battery
        self.model       = model
        self.productID   = productID
        self.colorID     = colorID
        self.eventID     = eventID
        self.revision    = revision
        self.kind        = kind
    }
}
