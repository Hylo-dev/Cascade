//
//  MacPowerSnapshot.swift
//  Cascade
//

/// MacPowerSnapshot feeds the charging notice from the built-in battery only;
/// accessory batteries and UPS devices must never masquerade as a Mac being
/// plugged in.
nonisolated struct MacPowerSnapshot: Equatable, Sendable {

    let percentage     : Int?
    let isExternalPower: Bool
    let isCharging     : Bool
    let isLowPowerMode : Bool
}
