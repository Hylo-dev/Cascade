//
//  PluginRecord.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// PluginRecord is everything the kernel tracks for one registered plugin: what it declared and
/// was granted, its supervisor state and health history, its pending events, its two budgets,
/// the wake it asked for and the sources it holds.
struct PluginRecord: Sendable {

    let manifest      : PluginManifest
    var grants        : Set<String>
    var status        = PluginStatus.idle
    var mailbox       = PluginMailbox()
    var history       = PluginHealthHistory()
    var cpu           : PluginCPUBudget
    var budget        : PluginPublicationBudget
    var throttledUntil: Duration
    var wake          : Date?
    var leased        : Set<String> = []

    init(
        manifest  : PluginManifest,
        grants    : Set<String>,
        at instant: Duration
    ) {
        self.manifest  = manifest
        self.grants    = grants
        cpu            = PluginCPUBudget(at: instant)
        budget         = PluginPublicationBudget(at: instant)
        throttledUntil = instant
    }

    /// isRunnable is true while the plugin may run: idle, handling or waiting out a retry.
    var isRunnable: Bool {
        switch status {
            case .idle, .handling, .retrying      : true
            case .disabledAfterHang, .quarantined: false
        }
    }
}
