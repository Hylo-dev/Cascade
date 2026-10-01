//
//  HostedPluginSource.swift
//  CascadeKit
//

import CascadeContracts

/// HostedPluginSource is a catalog source PluginHost implements, as the kernel's engine sees it:
/// starting it runs it in PluginHost through the shared executor, which starts it again in every
/// new host, and its states come back to the engine like any source's (§11).
public struct HostedPluginSource: PluginEventSource {

    private let name: String
    private let host: SharedHostExecutor

    public init(
        name: String,
        host: SharedHostExecutor
    ) {
        self.name = name
        self.host = host
    }

    public func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void) {
        host.startSource(name, emit: emit)
    }

    public func stop() {
        host.stopSource(name)
    }
}
