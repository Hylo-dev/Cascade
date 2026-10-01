//
//  PluginBatteryPalette.swift
//  CascadeKit
//

import SwiftUI

/// PluginBatteryPalette is the battery's colours: green while charging normally, yellow in Low
/// Power Mode, each with a dimmed remainder.
enum PluginBatteryPalette {

    static func fill(_ isLowPowerMode: Bool) -> Color {
        isLowPowerMode
            ? Color(red: 1, green: 0.95, blue: 0.18)
            : Color(red: 0.20, green: 0.88, blue: 0.46)
    }

    static func remainder(_ isLowPowerMode: Bool) -> Color {
        isLowPowerMode
            ? Color(red: 0.48, green: 0.36, blue: 0.20)
            : Color(red: 0.20, green: 0.88, blue: 0.46).opacity(0.38)
    }
}
