//
//  BatteryFace.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
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
                root: ViewThatFits(in: .vertical) {

                    large(state)

                    ViewThatFits(in: .horizontal) {

                        medium(state)

                        small(state)
                    }
                }
                .accessibilityLabel(label(of: state))
            )
        )
    }

    /// large is the 2x2 face: the battery and the status above the charge.
    private static func large(_ state: PluginPowerState) -> PluginNode {
        VStack(alignment: .leading, spacing: 1) {

            HStack(spacing: 5) {

                battery(state, height: 12)

                Text(status(of: state))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(tint(of: state))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }

            charge(state, size: 34)
        }
        .padding(.horizontal, 12)
        .frame(
            height   : largeHeight,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

    /// medium is the 2x1 face: the battery and the charge on one row.
    private static func medium(_ state: PluginPowerState) -> PluginNode {
        HStack(spacing: 6) {

            battery(state, height: 13)

            charge(state, size: 22)
        }
        .padding(.horizontal, 8)
        .frame(
            width    : mediumWidth,
            maxWidth : .infinity,
            maxHeight: .infinity,
            alignment: .leading
        )
    }

    /// small is the 1x1 face: the battery with its charge inside, and a bolt beside it while
    /// charging.
    private static func small(_ state: PluginPowerState) -> PluginNode {
        HStack(spacing: 2) {

            battery(state, height: 18, showsPercentage: true)

            if state.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(tint(of: state))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// charge is the percentage in white rounded digits that keep their width.
    private static func charge(
        _ state: PluginPowerState,
        size   : Double
    ) -> PluginNode {
        Text(state.percentage.map { "\($0)%" } ?? "—")
            .font(.system(size: size, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    /// battery is the kernel-drawn battery with the charging notice's proportions, at `height`,
    /// with its bolt while charging, or with its charge inside when it stands alone.
    private static func battery(
        _ state        : PluginPowerState,
        height         : Double,
        showsPercentage: Bool = false
    ) -> PluginNode {
        Component(
            id        : "power.battery",
            version   : 1,
            parameters: [
                "isLowPowerMode" : .bool(state.isLowPowerMode),
                "isCharging"     : .bool(state.isCharging && !showsPercentage),
                "showsPercentage": .bool(showsPercentage),
                "percentage"     : state.percentage.map { .number(Double($0)) },
            ]
        )
        .frame(width: height * 2.14, height: height)
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
