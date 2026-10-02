//
//  PluginBorderTint+NotchBorderAppearance.swift
//  CascadeKit
//

import CascadeContracts

extension PluginBorderTint {

    var notchBorderAppearance: NotchBorderAppearance {
        switch self {
            case .neutral         : .neutral
            case .connected       : .connected
            case .charging        : .charging
            case .chargingLowPower: .chargingLowPower
        }
    }
}
