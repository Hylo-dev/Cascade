//
//  PowerConnectionReducer.swift
//  CascadeKit
//

import CascadeContracts

/// PowerConnectionReducer treats a transition to external power as the event. Charge and Low
/// Power Mode changes only enrich it, so they cannot renew the notice's deadline. The first state
/// is a silent baseline, so launching, or restarting PluginHost, while plugged in shows nothing.
struct PowerConnectionReducer: Sendable {

    private var previous: PluginPowerState?

    mutating func receive(_ state: PluginPowerState) -> PowerConnectionUpdate? {
        guard state != previous else { return nil }

        let old  = previous
        previous = state
        guard let old else { return nil }

        if !state.isExternalPower {
            return old.isExternalPower ? .disconnected : nil
        }

        return old.isExternalPower ? .updated(state) : .connected(state)
    }
}
