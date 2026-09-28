//
//  SpotlightAccessibilityMonitoring.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices

/// SpotlightAccessibilityMonitoring keeps slow cross-process messaging outside
/// the animation actor. The renderer receives immutable snapshots only.
nonisolated protocol SpotlightAccessibilityMonitoring: AnyObject, Sendable {
    func start(processID: pid_t, generation: UInt64)
    func prepare(landingFrame: CGRect, desktopTop: CGFloat, screenSize: CGSize, generation: UInt64)
    func clearTarget(generation: UInt64)
    func stop()
}
