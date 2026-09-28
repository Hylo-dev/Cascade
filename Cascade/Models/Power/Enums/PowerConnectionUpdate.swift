//
//  PowerConnectionUpdate.swift
//  Cascade
//

nonisolated enum PowerConnectionUpdate: Equatable, Sendable {

    case connected(MacPowerSnapshot, revision: UInt64)
    case updated  (MacPowerSnapshot, revision: UInt64)
    case disconnected
}
