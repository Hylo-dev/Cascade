//
//  PluginHostStatus.swift
//  CascadeKit
//

/// PluginHostStatus is what settings show for the process that runs the plugins: connecting
/// while it starts or restarts, running once it answered its handshake, stopped once its
/// executor gave up on it after repeated crashes, until the user asks it to try again.
public enum PluginHostStatus: Equatable, Sendable {

    case connecting
    case running
    case stopped
}
