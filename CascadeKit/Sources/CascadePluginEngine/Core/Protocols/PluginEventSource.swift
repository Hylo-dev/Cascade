//
//  PluginEventSource.swift
//  CascadeKit
//

import CascadeContracts

/// PluginEventSource is one catalog source: an always-armed listener that costs nothing while
/// it waits (a notification, a socket, a kernel event) and emits the source's latest state when
/// it changes. The engine starts it with its first holder and stops it with its last; `start`
/// should emit the current state once, so a plugin starts from the truth.
public protocol PluginEventSource: Sendable {

    func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void)

    func stop()
}
