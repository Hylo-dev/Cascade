//
//  PluginComponentView.swift
//  CascadeKit
//

import CascadeContracts
import SwiftUI

/// PluginComponentView draws a tier-2 component from its parameters. A component the kernel does
/// not draw, or not at this version, keeps its frame and draws nothing, as a missing asset does.
/// `identifiers` is what Cascade offers plugins, so a feature that declares anything else is
/// unavailable.
struct PluginComponentView: View {

    static let identifiers: Set<String> = ["power.battery", "volume.level", "bluetooth.device", "bluetooth.battery"]

    let id        : String
    let version   : Int
    let parameters: [String: PluginValue]

    var body: some View {
        switch (id, version) {
            case ("power.battery", 1):
                PluginBatteryComponent(
                    percentage    : parameters["percentage"]?.number.map(Self.percent),
                    isLowPowerMode: parameters["isLowPowerMode"]?.bool ?? false
                )

            case ("volume.level", 1):
                PluginVolumeLevelComponent(level: parameters["level"]?.number.map(Self.percent) ?? 0)

            case ("bluetooth.device", 1):
                PluginBluetoothDeviceComponent(
                    model             : parameters["model"]?.string.flatMap(PluginBluetoothDeviceModel.init(rawValue:)) ?? .generic,
                    productID         : parameters["productID"]?.number.flatMap { UInt16(exactly: $0) },
                    colorID           : parameters["colorID"]?.number.flatMap { UInt8(exactly: $0) },
                    fallbackSymbolName: parameters["fallbackSymbol"]?.string
                )

            case ("bluetooth.battery", 1):
                PluginBluetoothBatteryComponent(
                    level      : parameters["level"]?.number.map(Self.percent),
                    isConnected: parameters["isConnected"]?.bool ?? false
                )

            default:
                Color.clear
        }
    }

    /// percent turns a parameter into a percentage. Validation only promises a finite number, so
    /// it is clamped before it becomes an Int, which would trap past Int's range and take the
    /// notch down with it; an identity, such as a product ID, is unknown unless it is an exact
    /// integer of its range.
    private static func percent(_ value: Double) -> Int {
        Int(min(100, max(0, value)).rounded())
    }
}
