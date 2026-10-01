//
//  PluginState.swift
//  CascadeKit
//

/// PluginState is what settings show for a plugin.
public enum PluginState: Equatable, Sendable {

    case active
    case disabledAfterHang
    case quarantined
}
