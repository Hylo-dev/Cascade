//
//  FixedHealthPolicy.swift
//  CascadeKit
//

@testable import CascadePluginEngine

/// FixedHealthPolicy answers every incident the same way, so a test reaches a state in one step
/// or proves that no incident was counted.
struct FixedHealthPolicy: PluginHealthPolicy {

    let answer: PluginHealthReaction

    func reaction(
        to incident: PluginIncident,
        history    : inout PluginHealthHistory,
        at instant : Duration
    ) -> PluginHealthReaction {
        answer
    }
}
