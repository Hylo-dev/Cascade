//
//  PluginInstant.swift
//  CascadeKit
//

import Foundation

/// PluginInstant is one reading of the two clocks the engine needs: the monotonic one for every
/// interval it measures (deadlines, retries, budgets), which never jumps, and the wall one only
/// for the wakes plugins ask for, which are civil times such as midnight.
struct PluginInstant: Equatable, Sendable {

    let wall     : Date
    let monotonic: Duration

    /// now reads the system clocks. Uptime stops while the Mac sleeps, so a watchdog does not
    /// fire as overdue the moment the lid opens.
    static func now() -> PluginInstant {
        PluginInstant(
            wall     : Date(),
            monotonic: .seconds(ProcessInfo.processInfo.systemUptime)
        )
    }
}
