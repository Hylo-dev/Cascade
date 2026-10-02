//
//  ScreenshotCoordinator.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import Observation
import os

/// ScreenshotCoordinator owns the lifetime of the native input wrapper, not a
/// capture pipeline. Preferences and permission checks run off the main actor;
/// only a fresh shortcut reaches the existing notch engine. Capture and recording
/// will use native ScreenCaptureKit services behind their own wrapper.
@MainActor
@Observable
final class ScreenshotCoordinator {

    private(set) var status = String(localized: "Screenshot shortcuts are off")
    private(set) var needsAccessibility = false

    @ObservationIgnored
    private let tap: any ScreenshotKeyTapping
    @ObservationIgnored
    private let onShortcut: @MainActor () -> Void
    private let onCancel  : @MainActor () -> Void
    @ObservationIgnored
    private let log = Logger(subsystem: "hylo.Cascade", category: "Screenshot")
    @ObservationIgnored
    private var readTask: Task<Void, Never>?
    @ObservationIgnored
    private var installedShortcuts: ScreenshotShortcuts?
    @ObservationIgnored
    private var workspaceToken: NSObjectProtocol?
    @ObservationIgnored
    private var unlockToken: NSObjectProtocol?
    @ObservationIgnored
    private var isEnabled = false
    @ObservationIgnored
    private var isLocked = false
    @ObservationIgnored
    private var hasRequestedAccessibility = false

    init(
        tap       : any ScreenshotKeyTapping = ScreenshotKeyTap(),
        onShortcut: @escaping @MainActor () -> Void,
        onCancel  : @escaping @MainActor () -> Void
    ) {
        self.tap        = tap
        self.onShortcut = onShortcut
        self.onCancel   = onCancel
    }

    func start() {
        guard !isEnabled else { return }

        isEnabled = true
        workspaceToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object : nil,
            queue  : .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  application.bundleIdentifier == "com.apple.systempreferences"
            else { return }

            Task { @MainActor [weak self] in self?.refresh() }
        }
        unlockToken = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsUnlocked"),
            object : nil,
            queue  : .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.isLocked = false
                self?.refresh()
            }
        }
        if hasRequestedAccessibility { refresh() }
        else { requestAccess() }
    }

    /// requestAccess prompts through macOS immediately, independently of audio
    /// consent. The native call returns without waiting for the user's answer;
    /// returning from System Settings or reopening the menu refreshes the tap.
    func requestAccess() {
        hasRequestedAccessibility = true
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let trusted = AXIsProcessTrustedWithOptions(options)
        log.notice("Screenshot Accessibility request trusted=\(trusted)")
        if !trusted, let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) {
            NSWorkspace.shared.open(url)
        }
        refresh()
    }

    /// refresh replaces the snapshot only when it changes, preserving the
    /// consumed key releases when the menu is opened while a shortcut is held.
    func refresh() {
        guard isEnabled, !isLocked else { return }

        readTask?.cancel()
        readTask = Task { [weak self] in
            let snapshot = await Task.detached(priority: .utility) {
                let preferences = UserDefaults(suiteName: "com.apple.symbolichotkeys")
                let bindings = preferences?.dictionary(forKey: "AppleSymbolicHotKeys") ?? [:]
                return (AXIsProcessTrusted(), ScreenshotShortcuts(preferences: bindings))
            }.value
            guard let self, self.isEnabled, !self.isLocked, !Task.isCancelled else { return }

            self.needsAccessibility = !snapshot.0
            guard snapshot.0 else {
                self.tap.stop()
                self.installedShortcuts = nil
                self.status = String(localized: "Allow Accessibility to open screenshot shortcuts in Cascade")
                self.log.notice("Screenshot interception requires Accessibility; native shortcuts remain active")
                return
            }
            if self.tap.isActive, self.installedShortcuts == snapshot.1 { return }

            let installed = self.tap.start(
                shortcuts : snapshot.1,
                onShortcut: { [weak self] in
                    guard let self, self.isEnabled, !self.isLocked else { return }

                    self.onShortcut()
                    self.log.notice("Screenshot shortcut opened the notch")
                },
                onCancel: { [weak self] in
                    guard let self, self.isEnabled, !self.isLocked else { return }

                    self.onCancel()
                },
                onDisabled: { [weak self] in
                    guard let self else { return }

                    self.tap.stop()
                    self.installedShortcuts = nil
                    self.status = String(localized: "Native screenshot shortcuts active · reopen the menu to try again")
                    self.log.error("Screenshot event tap disabled; native shortcuts restored")
                }
            )
            self.installedShortcuts = installed ? snapshot.1 : nil
            self.status = installed
                ? String(localized: "Screenshot shortcuts open the notch")
                : String(localized: "Native screenshot shortcuts active · reopen the menu to try again")
            self.log.notice("Screenshot interception active=\(installed)")
        }
    }

    func screenLocked() {
        isLocked = true
        readTask?.cancel()
        tap.stop()
        installedShortcuts = nil
    }

    /// setScreenPresented gives Escape to the screenshot page only while that
    /// page is visible. The tap does not require Cascade to steal keyboard focus.
    func setScreenPresented(_ isPresented: Bool) {
        tap.setCancellationEnabled(isPresented)
    }

    func stop() {
        isEnabled = false
        tap.setCancellationEnabled(false)
        readTask?.cancel()
        readTask = nil
        tap.stop()
        installedShortcuts = nil
        if let workspaceToken { NSWorkspace.shared.notificationCenter.removeObserver(workspaceToken) }
        if let unlockToken { DistributedNotificationCenter.default().removeObserver(unlockToken) }
        workspaceToken = nil
        unlockToken = nil
        isLocked = false
        needsAccessibility = false
        status = String(localized: "Screenshot shortcuts are off")
    }
}
