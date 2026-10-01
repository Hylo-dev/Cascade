//
//  PluginCatalogSource.swift
//  CascadeKit
//

import CascadeContracts

/// PluginCatalogSource is one catalog source PluginHost implements: an always-armed listener
/// that costs nothing while it waits and emits the source's state when it changes. `start`
/// emits the current state once, so the kernel starts from the truth.
public protocol PluginCatalogSource: Sendable {

    func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void)

    func stop()
}
