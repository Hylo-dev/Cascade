//
//  BatteryFace.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// BatteryFace is the battery widget's document, laid out as the clock is: a small line above a
/// large number. The small line is the kernel-drawn battery, with a bolt while charging, and the
/// status beside it; the charge has the whole row below, so even a full battery's "100%" keeps
/// its size instead of being cut short by whatever shares its row. A plugin never knows the size
/// of its tile, so both lines keep to one line and may shrink: the short 2x1 tile scales the
/// charge down a little, the tall 2x2 tile centres the two lines with room to spare. The status
/// takes the colour of the battery's fill, green while charging and yellow in Low Power Mode, and
/// VoiceOver reads the charge and the status.
enum BatteryFace {

    static func publication(for state: PluginPowerState) throws -> PluginPublication {
        try PluginPublication(
            feature : BatteryPlugin.feature,
            surface : .widget,
            document: PluginDocument(
                root: PluginNode(
                    .vStack(alignment: .leading, spacing: 1),
                    modifiers: [
                        .padding(.horizontal, length: 12),
                        .frame(width: nil, height: nil, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading),
                        .accessibilityLabel(label(of: state)),
                    ],
                    children: [
                        PluginNode(
                            .hStack(alignment: .center, spacing: 5),
                            children: [
                                battery(state),
                                PluginNode(
                                    .text(status(of: state)),
                                    modifiers: [
                                        .font(PluginFont(size: 12, weight: .semibold, design: .rounded)),
                                        .foregroundStyle(.color(tint(of: state))),
                                        .lineLimit(1),
                                        .minimumScaleFactor(0.7),
                                    ]
                                ),
                            ]
                        ),
                        PluginNode(
                            .text(state.percentage.map { "\($0)%" } ?? "—"),
                            modifiers: [
                                .font(PluginFont(size: 34, weight: .semibold, design: .rounded, monospacedDigit: true)),
                                .foregroundStyle(.color(.white)),
                                .lineLimit(1),
                                .minimumScaleFactor(0.5),
                            ]
                        ),
                    ]
                )
            )
        )
    }

    /// battery is the kernel-drawn battery with the charging notice's proportions, sized for the
    /// status line, and with its bolt while charging.
    private static func battery(_ state: PluginPowerState) -> PluginNode {
        var parameters: [String: PluginValue] = [
            "isLowPowerMode": .bool(state.isLowPowerMode),
            "isCharging"    : .bool(state.isCharging),
        ]
        if let percentage = state.percentage {
            parameters["percentage"] = .number(Double(percentage))
        }

        return PluginNode(
            .component(id: "power.battery", version: 1, parameters: parameters),
            modifiers: [.frame(width: 12 * 2.14, height: 12, maxWidth: nil, maxHeight: nil, alignment: .center)]
        )
    }

    private static func tint(of state: PluginPowerState) -> PluginColor {
        if state.isCharging { return PluginColor(red: 0.20, green: 0.88, blue: 0.46) }
        if state.isLowPowerMode { return PluginColor(red: 1, green: 0.82, blue: 0.27) }

        return PluginColor(red: 1, green: 1, blue: 1, opacity: 0.55)
    }

    private static func status(of state: PluginPowerState) -> String {
        if state.isCharging { return String(localized: "Charging", table: "BatteryWidget", bundle: .module) }
        if state.isExternalPower { return String(localized: "Plugged In", table: "BatteryWidget", bundle: .module) }
        if state.isLowPowerMode { return String(localized: "Low Power", table: "BatteryWidget", bundle: .module) }

        return String(localized: "On Battery", table: "BatteryWidget", bundle: .module)
    }

    private static func label(of state: PluginPowerState) -> String {
        let charge = state.percentage.map {
            String(localized: "Battery, \($0) percent", table: "BatteryWidget", bundle: .module)
        } ?? String(localized: "Battery unavailable", table: "BatteryWidget", bundle: .module)

        return "\(charge), \(status(of: state))"
    }
}
