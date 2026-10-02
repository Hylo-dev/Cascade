//
//  PluginHealthPolicy.swift
//  CascadeKit
//

/// PluginHealthPolicy turns incidents into reactions. The kernel owns each plugin's history and
/// passes it in, so a policy is a pure function, and tests can swap it for a fixed answer.
public protocol PluginHealthPolicy: Sendable {

    func reaction(
        to incident: PluginIncident,
        history    : inout PluginHealthHistory,
        at instant : Duration
    ) -> PluginHealthReaction
}
