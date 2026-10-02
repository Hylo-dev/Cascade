//
//  PluginRecord.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// PluginRecord is everything the kernel tracks for one registered plugin: what it declared and
/// was granted, its supervisor state and health history, its pending events, its budgets,
/// the wake it asked for, the sources it holds, and whether the user switched it on.
struct PluginRecord: Sendable {

    let manifest      : PluginManifest
    var grants        : Set<String>
    var status        = PluginStatus.idle
    var mailbox       = PluginMailbox()
    var history       = PluginHealthHistory()
    var cpu           : PluginCPUBudget
    var budget        : PluginPublicationBudget
    var noticeBudget  : PluginPublicationBudget
    var throttledUntil: Duration
    var wake          : Date?
    var leased        : Set<String> = []
    var isEnabled     = true

    init(
        manifest  : PluginManifest,
        grants    : Set<String>,
        at instant: Duration
    ) {
        self.manifest  = manifest
        self.grants    = grants
        cpu            = PluginCPUBudget(at: instant)
        budget         = PluginPublicationBudget(at: instant)
        noticeBudget   = PluginPublicationBudget(interval: PluginPublicationBudget.noticeInterval, at: instant)
        throttledUntil = instant
    }

    /// isRunnable is true while the plugin may run: switched on, and idle, handling or waiting out
    /// a retry.
    var isRunnable: Bool {
        guard isEnabled else { return false }

        return switch status {
            case .idle, .handling, .retrying      : true
            case .disabledAfterHang, .quarantined: false
        }
    }
}
