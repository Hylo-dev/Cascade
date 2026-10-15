//
//  PluginBluetoothDevice.swift
//  CascadeKit
//

/// PluginBluetoothDevice is one device a Bluetooth state lists as connected: its name, its
/// symbol and its charge, a percentage or unknown. A state lists at most `maximumCount` of them,
/// because a source event holds 32 flat fields, the state's own take 15 and each device three
/// more; a device connected after the fourth is left out until one of them leaves.
public struct PluginBluetoothDevice: Equatable, Sendable {

    public static let maximumCount = 4

    public let name        : String
    public let symbolName  : String
    public let batteryLevel: Int?

    public init(
        name        : String,
        symbolName  : String,
        batteryLevel: Int?
    ) {
        self.name         = name
        self.symbolName   = symbolName
        self.batteryLevel = batteryLevel.map { min(100, max(0, $0)) }
    }
}
