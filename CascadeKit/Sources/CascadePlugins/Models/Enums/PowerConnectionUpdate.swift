//
//  PowerConnectionUpdate.swift
//  CascadeKit
//

import CascadeContracts

/// PowerConnectionUpdate is what a power state means for the charging notice: the charger was
/// connected, its details changed while connected, or it was disconnected.
enum PowerConnectionUpdate: Equatable, Sendable {

    case connected(PluginPowerState)
    case updated(PluginPowerState)
    case disconnected
}
