//
//  CoreAudioVolumeMonitor.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import Foundation
import os

/// CoreAudioVolumeMonitor owns one stream generation at a time. Cancellation,
/// disable and deinitialization release listeners and the Quartz tap.
@MainActor
final class CoreAudioVolumeMonitor: VolumeMonitoring {
    private var worker: VolumeMonitorWorker?
    private var sessionID: UInt64 = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var activationObserver: NSObjectProtocol?
    private let permissionObserver = VolumeAccessibilityObserver()

    func start() -> AsyncStream<VolumeMonitorUpdate> {
        stop()
        sessionID &+= 1
        let currentSession = sessionID
        let pair = AsyncStream<VolumeMonitorUpdate>.makeStream(bufferingPolicy: .bufferingNewest(8))
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, sessionID == currentSession else { return }
                stop()
            }
        }
        let worker = VolumeMonitorWorker(sessionID: currentSession, continuation: pair.continuation)
        self.worker = worker
        observeLifecycle()
        worker.start()
        return pair.stream
    }

    func stop() {
        sessionID &+= 1
        removeLifecycleObservers()
        worker?.stop()
        worker = nil
    }

    func refreshPermissions() {
        worker?.refreshPermissions()
    }

    /// requestAccess opens the native consent flow at launch or from the menu.
    /// Existing grants are reused; permission observation refreshes the monitor.
    func requestAccess() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    private func observeLifecycle() {
        permissionObserver.start { [weak self] in self?.refreshPermissions() }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.worker?.suspend() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.worker?.resume() }
            })
        }
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    private func removeLifecycleObservers() {
        permissionObserver.stop()
        let center = NSWorkspace.shared.notificationCenter
        workspaceObservers.forEach { center.removeObserver($0) }
        workspaceObservers.removeAll()
        if let activationObserver { NotificationCenter.default.removeObserver(activationObserver) }
        activationObserver = nil
    }

    isolated deinit {
        removeLifecycleObservers()
        worker?.stop()
    }
}
