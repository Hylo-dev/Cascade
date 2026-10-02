//
//  BluetoothNotice.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// BluetoothNotice is the Bluetooth plugin's notice: the device on the leading side, Apple's own
/// artwork for a verified AirPods model or the device's symbol otherwise, and its charge as a
/// ring on the trailing side and when minimal, each centred in its slot. It lasts four seconds on
/// a neutral rim, and VoiceOver reads the device, what happened and every measured charge.
enum BluetoothNotice {

    static func publication(
        for state: PluginBluetoothState,
        delivery : PluginNoticeDelivery
    ) throws -> PluginPublication {
        try PluginPublication(
            feature : BluetoothPlugin.feature,
            surface : .notice,
            document: PluginDocument(
                root: Regions {

                    device(state)

                    battery(state)

                    battery(state)
                }
            ),
            notice  : PluginNoticeAttributes(
                duration          : 4,
                border            : .neutral,
                compactWidth      : 40,
                accessibilityLabel: "\(state.name), \(status(of: state)), \(batteryDescription(of: state))",
                delivery          : delivery
            )
        )
    }

    /// sample is the menu's preview: AirPods Pro with both earbuds and the case measured.
    static func sample() -> PluginBluetoothState {
        PluginBluetoothState(
            deviceID   : "demo-headphones",
            name       : text("AirPods · Preview"),
            symbolName : "airpodspro",
            isConnected: true,
            battery    : PluginBluetoothBattery(level: 68, left: 72, right: 68, caseLevel: 81),
            model      : .airPodsPro,
            productID  : 0x200E,
            colorID    : nil,
            eventID    : 0,
            revision   : 0,
            kind       : .connection,
            isAvailable: true
        )
    }

    /// device is the kernel-drawn artwork, 20 points square, for a model the system verified, or
    /// the device's class symbol at 14 points for anything it cannot identify.
    private static func device(_ state: PluginBluetoothState) -> PluginNode {
        guard state.model != .generic || state.productID != nil else {
            return Image(systemName: state.symbolName)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }

        return Component(
            id        : "bluetooth.device",
            version   : 1,
            parameters: [
                "model"         : .string(state.model.rawValue),
                "fallbackSymbol": .string(state.symbolName),
                "productID"     : state.productID.map { .number(Double($0)) },
                "colorID"       : state.colorID.map { .number(Double($0)) },
            ]
        )
        .frame(width: 20, height: 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// battery is the kernel-drawn ring, 18 points across; a disconnected device draws no arc.
    private static func battery(_ state: PluginBluetoothState) -> PluginNode {
        Component(
            id        : "bluetooth.battery",
            version   : 1,
            parameters: [
                "isConnected": .bool(state.isConnected),
                "level"      : state.battery?.level.map { .number(Double($0)) },
            ]
        )
        .frame(width: 18, height: 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func status(of state: PluginBluetoothState) -> String {
        guard state.isConnected else { return text("Disconnected") }

        switch state.kind {
            case .connection: return text("Connected")
            case .audioRoute: return text("Audio on Mac")
        }
    }

    private static func batteryDescription(of state: PluginBluetoothState) -> String {
        guard state.isConnected, let battery = state.battery, let level = battery.level else {
            return text("Battery unavailable")
        }

        var descriptions = [String(localized: "Battery, \(level) percent", table: "BluetoothNotice", bundle: .module)]
        if let left = battery.left {
            descriptions.append(String(localized: "Left, \(left) percent", table: "BluetoothNotice", bundle: .module))
        }
        if let right = battery.right {
            descriptions.append(String(localized: "Right, \(right) percent", table: "BluetoothNotice", bundle: .module))
        }
        if let caseLevel = battery.caseLevel {
            descriptions.append(String(localized: "Case, \(caseLevel) percent", table: "BluetoothNotice", bundle: .module))
        }

        return descriptions.joined(separator: ", ")
    }

    private static func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "BluetoothNotice", bundle: .module)
    }
}
