//
//  PluginState.swift
//  CascadeKit
//

/// PluginState is what settings show for a plugin: running, stopped by its health, or switched
/// off by the user, which is shown ahead of its health.
public enum PluginState: Equatable, Sendable {

    case active
    case disabledAfterHang
    case quarantined
    case switchedOff
}
