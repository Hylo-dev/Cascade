//
//  DevicesFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation

/// DevicesFace is the devices widget's document, a face for the tall 2x2 tile and one for the
/// short 2x1 tile, the taller first. Each lists the connected devices in the order they
/// connected, a row each: the device's symbol, its name, and, when the device reports its
/// charge, the charge beside the kernel's ring. The tall face lists up to four devices, every
/// one a state can carry, and the short face the first two. With nothing connected it says so,
/// and on a Mac whose Bluetooth does not work it says Bluetooth is off. The ring is hidden from
/// VoiceOver, so the face reads every device and every known charge.
///
/// Under a 38-point notch a 2x2 tile is 110 by 68 points and a 2x1 tile 110 by 31. A row is
/// about 12 points tall, so four fit the 66 points of the tall face and two the short tile. Every
/// part of a row has a fixed width that adds up to 102 points, so a long name is cut short on its
/// one line instead of pushing the charge off the tile, and the charge has a slot that holds
/// "100%" whole. A device without a charge gives its name the room the charge would take. The
/// tall face is 66 points tall: ViewThatFits measures a face with the tile's width already given,
/// and a fixed height keeps the choice on the tile.
enum DevicesFace {

    static let largeHeight = 66.0

    private static let padding     = 4.0
    private static let rowWidth    = 102.0
    private static let gap         = 2.0
    private static let symbolWidth = 11.0
    private static let chargeWidth = 25.0
    private static let ringSize    = 9.0

    static func publication(for state: PluginBluetoothState) throws -> PluginPublication {
        try PluginPublication(
            feature : DevicesPlugin.feature,
            surface : .widget,
            document: PluginDocument(
                root: ViewThatFits(in: .vertical) {

                    list(state, upTo: PluginBluetoothDevice.maximumCount, spacing: 4)
                        .frame(
                            height   : largeHeight,
                            maxWidth : .infinity,
                            maxHeight: .infinity,
                            alignment: .leading
                        )

                    list(state, upTo: 2, spacing: 2)
                        .frame(
                            maxWidth : .infinity,
                            maxHeight: .infinity,
                            alignment: .leading
                        )
                }
                .accessibilityLabel(label(of: state))
            )
        )
    }

    /// list is a face's rows, the first `count` devices, or what to say when there are none.
    private static func list(
        _ state   : PluginBluetoothState,
        upTo count: Int,
        spacing   : Double
    ) -> PluginNode {
        VStack(alignment: .leading, spacing: spacing) {

            if let message = message(for: state) {
                Text(message)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            } else {
                for device in state.connectedDevices.prefix(count) {
                    row(device)
                }
            }
        }
        .padding(.horizontal, padding)
    }

    /// row is one device: its symbol, its name in white, and its charge, dimmed, beside the
    /// kernel's ring when the device reports one.
    private static func row(_ device: PluginBluetoothDevice) -> PluginNode {
        let nameWidth = device.batteryLevel == nil
            ? rowWidth - symbolWidth - gap
            : rowWidth - symbolWidth - chargeWidth - ringSize - 3 * gap

        return HStack(spacing: gap) {

            Image(systemName: device.symbolName)
                .font(.system(size: 9, weight: .regular))
                .foregroundStyle(.white)
                .frame(width: symbolWidth)

            Text(device.name)
                .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(width: nameWidth, alignment: .leading)

            if let level = device.batteryLevel {
                Text("\(level)%")
                    .font(.system(size: 8, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .frame(width: chargeWidth, alignment: .trailing)

                Component(
                    id        : "bluetooth.battery",
                    version   : 1,
                    parameters: [
                        "isConnected": .bool(true),
                        "level"      : .number(Double(level)),
                    ]
                )
                .frame(width: ringSize, height: ringSize)
            }
        }
    }

    /// message is what a face says instead of rows: that Bluetooth is off, or that nothing is
    /// connected.
    private static func message(for state: PluginBluetoothState) -> String? {
        if !state.isAvailable { return String(localized: "Bluetooth is off", table: "Plugins", bundle: .module) }
        if state.connectedDevices.isEmpty { return String(localized: "No devices", table: "Plugins", bundle: .module) }

        return nil
    }

    /// label reads every connected device and its charge, when it reports one.
    private static func label(of state: PluginBluetoothState) -> String {
        if let message = message(for: state) { return message }

        return state.connectedDevices
            .map { device in
                guard let level = device.batteryLevel else { return device.name }

                return String(localized: "\(device.name), battery \(level) percent", table: "Plugins", bundle: .module)
            }
            .joined(separator: ", ")
    }
}
