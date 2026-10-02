//
//  PluginEngineStatus.swift
//  CascadeKit
//

import CascadeContracts

/// PluginEngineStatus is everything settings show about the engine: each registered plugin's
/// state and the host's.
public struct PluginEngineStatus: Equatable, Sendable {

    public let plugins: [PluginID: PluginState]
    public let host   : PluginHostStatus
}
