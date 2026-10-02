//
//  VolumeTapObservers.swift
//  Cascade
//

import AppKit

/// VolumeTapObservers are the observers only the volume key tap needs: sleep and
/// session switches suspend it and bring it back, and the app's activation and
/// Accessibility changes recheck whether it may be installed. The level is
/// observed without them, so the monitor runs them only while the tap may run,
/// and an app that shows the volume without replacing its HUD is not woken by
/// every application that loses focus.
@MainActor
final class VolumeTapObservers {

    private let workspace  : NotificationCenter
    private let application: NotificationCenter
    private let permissions: VolumeAccessibilityObserver

    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    init(
        workspace  : NotificationCenter = NSWorkspace.shared.notificationCenter,
        application: NotificationCenter = .default,
        permissions: VolumeAccessibilityObserver = VolumeAccessibilityObserver()
    ) {
        self.workspace   = workspace
        self.application = application
        self.permissions = permissions
    }

    var isObserving: Bool {
        !tokens.isEmpty
    }

    /// start replaces any earlier observation with one that calls `refresh`
    /// when the tap's permission may have changed, `suspend` when the Mac sleeps
    /// or the session goes away, and `resume` when either comes back.
    func start(
        refresh: @escaping @MainActor @Sendable () -> Void,
        suspend: @escaping @MainActor @Sendable () -> Void,
        resume : @escaping @MainActor @Sendable () -> Void
    ) {
        stop()

        permissions.start(onChange: refresh)
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observe(name, on: workspace, with: suspend)
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observe(name, on: workspace, with: resume)
        }
        observe(NSApplication.didBecomeActiveNotification, on: application, with: refresh)
    }

    func stop() {
        permissions.stop()
        for (center, token) in tokens {
            center.removeObserver(token)
        }
        tokens.removeAll()
    }

    private func observe(
        _ name   : Notification.Name,
        on center: NotificationCenter,
        with call: @escaping @MainActor @Sendable () -> Void
    ) {
        let token = center.addObserver(
            forName: name,
            object : nil,
            queue  : .main
        ) { _ in
            MainActor.assumeIsolated { call() }
        }
        tokens.append((center, token))
    }

    isolated deinit { stop() }
}
