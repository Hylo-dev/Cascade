//
//  VolumeAccessibilityObserver.swift
//  Cascade
//

import AppKit

/// VolumeAccessibilityObserver exists because an accessory app does not
/// necessarily activate when its status menu opens. Observe permission changes
/// independently of mounted SwiftUI views. The private system notification is a
/// hint only; the worker rechecks real trust.
@MainActor
final class VolumeAccessibilityObserver {

    private let permissions: NotificationCenter
    private let workspace  : NotificationCenter
    private let settleDelay: Duration

    private var permissionToken: NSObjectProtocol?
    private var workspaceToken : NSObjectProtocol?
    private var pendingRefresh : Task<Void, Never>?

    init(
        permissions: NotificationCenter = DistributedNotificationCenter.default(),
        workspace  : NotificationCenter = NSWorkspace.shared.notificationCenter,
        settleDelay: Duration = .milliseconds(150)
    ) {
        self.permissions = permissions
        self.workspace   = workspace
        self.settleDelay = settleDelay
    }

    func start(onChange: @escaping @MainActor @Sendable () -> Void) {
        stop()

        permissionToken = permissions.addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object : nil,
            queue  : .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.schedule(onChange) }
        }

        workspaceToken = workspace.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object : nil,
            queue  : .main
        ) { [weak self] notification in
            let isSettings = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?
                .bundleIdentifier == "com.apple.systempreferences"
            guard isSettings else { return }

            MainActor.assumeIsolated {
                self?.schedule(onChange)
            }
        }
    }

    func stop() {
        pendingRefresh?.cancel()
        pendingRefresh = nil

        if let permissionToken { permissions.removeObserver(permissionToken) }
        if let workspaceToken { workspace.removeObserver(workspaceToken) }
        permissionToken = nil
        workspaceToken  = nil
    }

    private func schedule(_ onChange: @escaping @MainActor @Sendable () -> Void) {
        // Coalesce a burst without a periodic permission poll. The task holds
        // no owner and cannot clear a newer task's cancellation handle.
        pendingRefresh?.cancel()

        let delay = settleDelay
        pendingRefresh = Task {
            do { try await Task.sleep(for: delay) } catch { return }
            guard !Task.isCancelled else { return }

            onChange()
        }
    }

    isolated deinit { stop() }
}
