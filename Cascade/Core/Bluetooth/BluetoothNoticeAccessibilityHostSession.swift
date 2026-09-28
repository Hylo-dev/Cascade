//
//  BluetoothNoticeAccessibilityHostSession.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices

/// Immutable host handles are messaged only by the worker; the main actor manages run-loop sources.
nonisolated final class BluetoothNoticeAccessibilityHostSession: @unchecked Sendable {

    let bundleID     : String
    let observer     : AXObserver
    let application  : AXUIElement
    let notifications: [String]

    init(
        bundleID     : String,
        observer     : AXObserver,
        application  : AXUIElement,
        notifications: [String]
    ) {
        self.bundleID      = bundleID
        self.observer      = observer
        self.application   = application
        self.notifications = notifications
    }
}
