//
//  PluginExecutorEvent.swift
//  CascadeKit
//

/// PluginExecutorEvent is a change in whether an executor's host can run plugins.
public enum PluginExecutorEvent: Equatable, Sendable {

    case available   // A host completed its handshake and loaded the plugins.
    case unavailable // The host is gone, or not there yet.
    case abandoned   // The host was given up on after repeated crashes, until a restart.
}
