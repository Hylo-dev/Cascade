//
//  FocusedApplicationMonitoring.swift
//  CascadeKit
//

import AppKit
@preconcurrency import ApplicationServices

/// FocusedApplicationMonitoring owns public workspace activation observation.
/// It also reports System Settings deactivation so returning from the privacy
/// pane rechecks trust without a private permission notification or polling.
@MainActor
protocol FocusedApplicationMonitoring: AnyObject {
    var onChange: (() -> Void)? { get set }
    var frontmostApplication: FocusedApplication? { get }

    func start()
    func stop()
}
