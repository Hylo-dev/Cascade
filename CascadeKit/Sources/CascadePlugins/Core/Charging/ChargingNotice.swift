//
//  ChargingNotice.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// ChargingNotice is the charging plugin's notice: the status on the leading side, the charge and
/// the battery on the trailing side, the battery alone when minimal. The rim and the charge glow
/// green, or yellow in Low Power Mode, and VoiceOver reads the status, the charge and the mode.
enum ChargingNotice {

    static func publication(
        for state: PluginPowerState,
        delivery : PluginNoticeDelivery
    ) throws -> PluginPublication {
        try PluginPublication(
            feature : ChargingPlugin.feature,
            surface : .notice,
            document: PluginDocument(
                root: PluginNode(
                    .regions,
                    children: [
                        PluginNode(
                            .text(status(of: state)),
                            modifiers: [
                                .font(PluginFont(style: .callout)),
                                .foregroundStyle(.color(.white)),
                                .lineLimit(1),
                                .minimumScaleFactor(10.0 / 12.0),
                            ]
                        ),
                        PluginNode(
                            .hStack(alignment: .center, spacing: 6),
                            children: [
                                PluginNode(
                                    .text(state.percentage.map { "\($0)%" } ?? "—"),
                                    modifiers: [
                                        .font(PluginFont(style: .callout, monospacedDigit: true)),
                                        .foregroundStyle(.color(tint(state.isLowPowerMode))),
                                        .lineLimit(1),
                                        .minimumScaleFactor(10.0 / 12.0),
                                    ]
                                ),
                                battery(state),
                            ]
                        ),
                        battery(state),
                    ]
                )
            ),
            notice  : PluginNoticeAttributes(
                duration          : 4,
                border            : state.isLowPowerMode ? .chargingLowPower : .charging,
                compactWidth      : 116,
                accessibilityLabel: label(of: state),
                delivery          : delivery
            )
        )
    }

    /// battery is the kernel-drawn battery, twelve points high, with the old icon's proportions.
    private static func battery(_ state: PluginPowerState) -> PluginNode {
        var parameters: [String: PluginValue] = ["isLowPowerMode": .bool(state.isLowPowerMode)]
        if let percentage = state.percentage {
            parameters["percentage"] = .number(Double(percentage))
        }

        return PluginNode(
            .component(id: "power.battery", version: 1, parameters: parameters),
            modifiers: [.frame(width: 12 * 2.14, height: 12, maxWidth: nil, maxHeight: nil, alignment: .center)]
        )
    }

    private static func tint(_ isLowPowerMode: Bool) -> PluginColor {
        isLowPowerMode
            ? PluginColor(red: 1, green: 0.82, blue: 0.27)
            : PluginColor(red: 0.20, green: 0.88, blue: 0.46)
    }

    private static func status(of state: PluginPowerState) -> String {
        if state.isCharging { return String(localized: "Charging", table: "ChargingNotice", bundle: .module) }
        if state.percentage == 100 { return String(localized: "Charged", table: "ChargingNotice", bundle: .module) }
        return String(localized: "Plugged In", table: "ChargingNotice", bundle: .module)
    }

    private static func label(of state: PluginPowerState) -> String {
        let battery = state.percentage.map {
            String(localized: "Battery, \($0) percent", table: "ChargingNotice", bundle: .module)
        } ?? String(localized: "Battery unavailable", table: "ChargingNotice", bundle: .module)
        let lowPower = state.isLowPowerMode
            ? ", " + String(localized: "Low Power Mode", table: "ChargingNotice", bundle: .module)
            : ""

        return "\(status(of: state)), \(battery)\(lowPower)"
    }
}
