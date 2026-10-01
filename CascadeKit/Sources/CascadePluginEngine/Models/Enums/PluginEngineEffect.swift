//
//  PluginEngineEffect.swift
//  CascadeKit
//

import CascadeContracts

/// PluginEngineEffect is one thing the kernel asks the engine to do once the kernel's lock is
/// released. The kernel decides and the engine calls out, so no plugin, source or sink ever
/// runs while the kernel's state is held.
enum PluginEngineEffect: Equatable, Sendable {

    case start(PluginID, entryPoint: String)
    case dispatch(PluginID, PluginEvent, token: UInt64)
    case stop(PluginID)
    case startSource(String)
    case stopSource(String)
    case deliver([PluginPublicationChange])
    case reject(PluginActionRequest)
}
