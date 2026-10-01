//
//  PluginBorderTint.swift
//  CascadeKit
//

/// PluginBorderTint is the colour a notice asks the notch's rim to take while it shows: a
/// device that connected, a Mac that is charging, or charging in Low Power Mode.
public enum PluginBorderTint: String, Codable, Hashable, Sendable {

    case connected
    case charging
    case chargingLowPower
}
