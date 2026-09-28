//
//  MacPowerSnapshot.swift
//  Cascade
//

/// Only the built-in battery feeds the charging notice; accessory batteries
/// and UPS devices must never masquerade as a Mac being plugged in.
nonisolated struct MacPowerSnapshot: Equatable, Sendable {

    let percentage     : Int?
    let isExternalPower: Bool
    let isCharging     : Bool
    let isLowPowerMode : Bool
}
