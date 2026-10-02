//
//  PluginBorderTint.swift
//  CascadeKit
//

/// PluginBorderTint is the colour a notice asks the notch's rim to take while it shows: a
/// device that connected, a Mac that is charging, or charging in Low Power Mode. `neutral` keeps
/// the ordinary rim even while another signal, such as a network that just connected, would
/// tint it.
public enum PluginBorderTint: String, Codable, Hashable, Sendable {

    case neutral
    case connected
    case charging
    case chargingLowPower
}
