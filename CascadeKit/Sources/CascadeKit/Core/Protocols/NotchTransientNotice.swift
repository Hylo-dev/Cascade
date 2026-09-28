//
//  NotchTransientNotice.swift
//  CascadeKit
//

import Foundation

/// NotchTransientNotice describes one completed status change, such as an
/// accessory connecting. It cannot become an indefinite Live Activity. Coalesce
/// repeated identity/revision, avoid duplicate system notifications and request
/// attention only when useful.
@MainActor
public protocol NotchTransientNotice: NotchActivity {

    /// Short duration, capped at ten seconds by Cascade (not an Apple limit).
    var displayDuration: TimeInterval { get }
}
