//
//  BatteryFace.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// BatteryFace is the battery widget's document, in a face for each size the widget comes in;
/// the plugin never learns which one the user picked, so it lists them from largest to smallest
/// and the kernel shows the first that fits. The tall 2x2 tile sets a small line above a large
/// charge, as the clock does: the kernel-drawn battery, with a bolt while charging, and the
/// status beside it, and the charge with a whole row of its own, so even "100%" keeps its size.
/// The short 2x1 tile puts the battery and the charge on one row, and the small 1x1 tile is the
/// battery alone with its charge inside it, and a bolt beside it while charging. The status takes the colour of the battery's fill, green
/// while charging and yellow in Low Power Mode, and VoiceOver reads the charge and the status.
///
/// The large face is 56 points tall and the medium one 100 points wide. ViewThatFits measures a
/// face against the tile with its other side already given, and text that may shrink would let
/// the large face pass for a small tile; fixed thresholds make the choice follow the tile.
enum BatteryFace {

    static let largeHeight = 56.0
    static let mediumWidth = 100.0


    static func publication(for state: PluginPowerState) throws -> PluginPublication {
        try PluginPublication(
            feature : BatteryPlugin.feature,
            surface : .widget,
            document: PluginDocument(
                root: PluginNode(
                    .viewThatFits(axes: .vertical),
                    modifiers: [.accessibilityLabel(label(of: state))],
                    children : [
                        large(state),
                        PluginNode(.viewThatFits(axes: .horizontal), children: [medium(state), small(state)]),
                    ]
                )
            )
        )
    }

    /// large is the 2x2 face: the battery and the status above the charge.
    private static func large(_ state: PluginPowerState) -> PluginNode {
        PluginNode(
            .vStack(alignment: .leading, spacing: 1),
            modifiers: [
                .padding(.horizontal, length: 12),
                .frame(width: nil, height: largeHeight, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading),
            ],
            children: [
                PluginNode(
                    .hStack(alignment: .center, spacing: 5),
                    children: [
                        battery(state, height: 12),
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
                charge(state, size: 34),
            ]
        )
    }

    /// medium is the 2x1 face: the battery and the charge on one row.
    private static func medium(_ state: PluginPowerState) -> PluginNode {
        PluginNode(
            .hStack(alignment: .center, spacing: 6),
            modifiers: [
                .padding(.horizontal, length: 8),
                .frame(width: mediumWidth, height: nil, maxWidth: .infinity, maxHeight: .infinity, alignment: .leading),
            ],
            children: [battery(state, height: 13), charge(state, size: 22)]
        )
    }

    /// small is the 1x1 face: the battery with its charge inside, and a bolt beside it while
    /// charging.
    private static func small(_ state: PluginPowerState) -> PluginNode {
        var children = [battery(state, height: 18, showsPercentage: true)]
        if state.isCharging {
            children.append(
                PluginNode(
                    .symbol(name: "bolt.fill"),
                    modifiers: [
                        .font(PluginFont(size: 10, weight: .bold)),
                        .foregroundStyle(.color(tint(of: state))),
                    ]
                )
            )
        }

        return PluginNode(
            .hStack(alignment: .center, spacing: 2),
            modifiers: [.frame(width: nil, height: nil, maxWidth: .infinity, maxHeight: .infinity, alignment: .center)],
            children : children
        )
    }

    /// charge is the percentage in white rounded digits that keep their width.
    private static func charge(
        _ state: PluginPowerState,
        size   : Double
    ) -> PluginNode {
        PluginNode(
            .text(state.percentage.map { "\($0)%" } ?? "—"),
            modifiers: [
                .font(PluginFont(size: size, weight: .semibold, design: .rounded, monospacedDigit: true)),
                .foregroundStyle(.color(.white)),
                .lineLimit(1),
                .minimumScaleFactor(0.5),
            ]
        )
    }

    /// battery is the kernel-drawn battery with the charging notice's proportions, at `height`,
    /// with its bolt while charging, or with its charge inside when it stands alone.
    private static func battery(
        _ state        : PluginPowerState,
        height         : Double,
        showsPercentage: Bool = false
    ) -> PluginNode {
        var parameters: [String: PluginValue] = [
            "isLowPowerMode" : .bool(state.isLowPowerMode),
            "isCharging"     : .bool(state.isCharging && !showsPercentage),
            "showsPercentage": .bool(showsPercentage),
        ]
        if let percentage = state.percentage {
            parameters["percentage"] = .number(Double(percentage))
        }

        return PluginNode(
            .component(id: "power.battery", version: 1, parameters: parameters),
            modifiers: [.frame(width: height * 2.14, height: height, maxWidth: nil, maxHeight: nil, alignment: .center)]
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
