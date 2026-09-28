//
//  WorkspaceFocusedApplicationMonitor.swift
//  CascadeKit
//

import AppKit
@preconcurrency import ApplicationServices

/// WorkspaceFocusedApplicationMonitor translates public NSWorkspace events
/// into cheap invalidations. The AX worker remains responsible for real trust.
@MainActor
final class WorkspaceFocusedApplicationMonitor: NSObject, FocusedApplicationMonitoring {

    var onChange: (() -> Void)?

    private let workspace: NSWorkspace

    private var isStarted = false

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace

        super.init()
    }

    var frontmostApplication: FocusedApplication? {
        guard let application = workspace.frontmostApplication else { return nil }

        return FocusedApplication(
            processID       : application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier
        )
    }

    func start() {
        guard !isStarted else { return }

        isStarted = true

        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated),
            name    : NSWorkspace.didActivateApplicationNotification,
            object  : nil
        )
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDeactivated),
            name    : NSWorkspace.didDeactivateApplicationNotification,
            object  : nil
        )
    }

    func stop() {
        guard isStarted else { return }

        workspace.notificationCenter.removeObserver(self)
        isStarted = false
    }

    @objc
    private func applicationActivated() {
        onChange?()
    }

    @objc
    private func applicationDeactivated(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        guard application?.bundleIdentifier == "com.apple.systempreferences" else { return }

        onChange?()
    }

    deinit {
        workspace.notificationCenter.removeObserver(self)
    }
}
