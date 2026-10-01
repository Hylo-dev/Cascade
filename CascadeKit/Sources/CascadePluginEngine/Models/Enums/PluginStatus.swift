//
//  PluginStatus.swift
//  CascadeKit
//

/// PluginStatus is the supervisor's state for one plugin. Idle and handling alternate while it
/// is healthy, the token naming the one dispatch in flight and the deadline its watchdog;
/// retrying pauses it after a throw; the two stopped states last until the user re-enables it.
enum PluginStatus: Equatable, Sendable {

    case idle
    case handling(token: UInt64, deadline: Duration)
    case retrying(until: Duration)
    case disabledAfterHang
    case quarantined
}
