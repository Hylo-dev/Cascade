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

    static let identifiers: Set<String> = ["power.battery"]

    let id        : String
    let version   : Int
    let parameters: [String: PluginValue]

    var body: some View {
        switch (id, version) {
            case ("power.battery", 1):
                PluginBatteryComponent(
                    percentage    : parameters["percentage"]?.number.map { Int($0.rounded()) },
                    isLowPowerMode: parameters["isLowPowerMode"]?.bool ?? false
                )

            default:
                Color.clear
        }
    }
}
