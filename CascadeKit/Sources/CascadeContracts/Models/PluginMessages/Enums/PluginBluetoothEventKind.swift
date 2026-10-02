//
//  PluginBluetoothEventKind.swift
//  CascadeKit
//

/// PluginBluetoothEventKind tells what a Bluetooth event was: a link that connected or
/// disconnected, or audio that came back to the Mac while the link to the device never dropped.
public enum PluginBluetoothEventKind: String, Codable, Hashable, Sendable {

    case connection
    case audioRoute
}
