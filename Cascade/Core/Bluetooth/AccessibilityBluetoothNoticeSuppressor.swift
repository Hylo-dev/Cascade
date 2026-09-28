//
//  AccessibilityBluetoothNoticeSuppressor.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import Observation
import os

/// Observes identified SystemBannerUI subtrees plus the legacy Control Center floating notice.
/// AX delivers an already-presented view: this is selective dismissal, not pre-presentation prevention.
/// No shared MenuBarAgent window or system notification preference is ever changed.
@Observable
@MainActor
final class AccessibilityBluetoothNoticeSuppressor: BluetoothNoticeSuppressing {
    private(set) var status: BluetoothNoticeSuppressionStatus = .stopped

    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var worker: BluetoothNoticeAccessibilityWorker?
    @ObservationIgnored private var session: BluetoothNoticeObservationSession?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var observedProcesses: [String: pid_t] = [:]
    @ObservationIgnored private var workspaceTokens: [NSObjectProtocol] = []
    @ObservationIgnored private var permissionToken: NSObjectProtocol?

    private var supportedHosts: [String] {
        if #available(macOS 27.0, *) { ["com.apple.controlcenter", "com.apple.MenuBarAgent"] }
        else { ["com.apple.controlcenter"] }
    }

    /// Reuses a healthy observer; host restarts and permission events recreate only the AX session.
    func start() {
        isEnabled = true
        installLifecycleObservers()
        guard AXIsProcessTrusted() else {
            resetSession()
            status = .permissionRequired
            return
        }
        var processes: [String: pid_t] = [:]
        for bundleID in supportedHosts {
            if let process = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                processes[bundleID] = process.processIdentifier
            }
        }
        guard !processes.isEmpty else {
            resetSession()
            status = .unsupported("The system Bluetooth banner host is not running.")
            return
        }
        if worker != nil, observationTask != nil, observedProcesses == processes { return }
        resetSession()
        let currentGeneration = generation
        let newWorker = BluetoothNoticeAccessibilityWorker()
        worker = newWorker
        observedProcesses = processes
        observationTask = Task { [weak self] in
            do {
                let newSession = try await newWorker.start(processes: processes)
                guard !Task.isCancelled, self?.generation == currentGeneration else {
                    await newWorker.stop()
                    return
                }
                self?.session = newSession
                self?.observedProcesses = processes
                for host in newSession.hosts {
                    CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(host.observer), .commonModes)
                }
                self?.status = .observing
                for await _ in newSession.signal.events {
                    guard !Task.isCancelled else { break }
                    let result = await newWorker.inspectExpectedNotice()
                    guard self?.generation == currentGeneration else { break }
                    if let result { self?.status = result }
                }
            } catch let error as BluetoothNoticeAccessibilityError {
                guard let self, self.generation == currentGeneration else { return }
                self.resetSession()
                self.status = error.status
            } catch {
                guard let self, self.generation == currentGeneration else { return }
                self.resetSession()
                self.status = .failure(error.localizedDescription)
            }
        }
    }

    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
        start()
    }

    func stop() {
        isEnabled = false
        resetSession()
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        workspaceTokens.removeAll()
        if let permissionToken { DistributedNotificationCenter.default().removeObserver(permissionToken) }
        permissionToken = nil
        status = .stopped
    }

    private func resetSession() {
        generation += 1
        observationTask?.cancel()
        observationTask = nil
        if let session {
            session.signal.cancel()
            for host in session.hosts {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(host.observer), .commonModes)
            }
        }
        session = nil
        observedProcesses.removeAll()
        if let worker { Task { await worker.stop() } }
        worker = nil
    }

    /// These observers are idle between real lifecycle events; no process or permission polling.
    private func installLifecycleObservers() {
        guard workspaceTokens.isEmpty else { return }
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didDeactivateApplicationNotification] {
            workspaceTokens.append(NSWorkspace.shared.notificationCenter.addObserver(
                forName: name, object: nil, queue: .main
            ) { [weak self] notification in
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                      let bundleID = app.bundleIdentifier else { return }
                let isSettingsDeparture = name == NSWorkspace.didDeactivateApplicationNotification
                    && bundleID == "com.apple.systempreferences"
                let isBannerHost = name != NSWorkspace.didDeactivateApplicationNotification
                    && ["com.apple.controlcenter", "com.apple.MenuBarAgent"].contains(bundleID)
                guard isSettingsDeparture || isBannerHost else { return }
                Task { @MainActor [weak self] in
                    guard let self, self.isEnabled else { return }
                    self.start()
                }
            })
        }
        permissionToken = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                    guard let self, self.isEnabled else { return }
                    self.start()
                }
        }
    }

    func expectConnection(deviceName: String) {
        guard let worker else { return }
        let currentGeneration = generation
        Task { [weak self] in
            let result = await worker.expectConnection(deviceName: deviceName)
            guard let self, self.generation == currentGeneration else { return }
            if let result { self.status = result }
        }
    }

    isolated deinit {
        observationTask?.cancel()
        for token in workspaceTokens { NSWorkspace.shared.notificationCenter.removeObserver(token) }
        if let permissionToken { DistributedNotificationCenter.default().removeObserver(permissionToken) }
        if let session {
            session.signal.cancel()
            for host in session.hosts {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(host.observer), .commonModes)
            }
        }
        if let worker { Task { await worker.stop() } }
    }
}
