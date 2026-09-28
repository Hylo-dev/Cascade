//
//  NotchBorderAppearance.swift
//  CascadeKit
//



/// NotchBorderAppearance describes the semantic tint of the shared glass rim.
/// The renderer owns colors and accessibility adaptations; providers only
/// declare meaning, without importing platform color types into their state.
public nonisolated enum NotchBorderAppearance: Equatable, Sendable {
    case neutral
    case connected
    case charging
    case chargingLowPower
}
