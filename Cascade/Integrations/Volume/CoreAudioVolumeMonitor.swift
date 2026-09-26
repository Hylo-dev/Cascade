//
//  CoreAudioVolumeMonitor.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import Foundation
import os

/// VolumeMonitorWorker confines mutable audio state to its serial queue.
/// The tap must decide synchronously whether to swallow a key; only its private
/// thread waits for CoreAudio, while observation reaches UI as Sendable values.
/// Unchecked Sendable is limited to this queue-confined worker boundary.
nonisolated private final class VolumeMonitorWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Cascade.Volume", qos: .userInitiated)
    private let sessionID: UInt64
    private let continuation: AsyncStream<VolumeMonitorUpdate>.Continuation
    private var audio: CoreAudioSystemVolume?
    private var tap: VolumeMediaKeyTap?
    private var isRunning = false
    private var isSuspended = false
    private var tapIsActive = false
    private var tapGeneration: UInt64 = 0
    private var reducer = VolumeChangeReducer()
    private var router = VolumeKeyRouter()
    private var lastStatus: VolumeMonitoringStatus?
    private let logger = Logger(subsystem: "hylo.Cascade", category: "VolumeMonitor")

    init(
        sessionID   : UInt64,
        continuation: AsyncStream<VolumeMonitorUpdate>.Continuation
    ) {
        self.sessionID = sessionID
        self.continuation = continuation
    }

    func start() {
        queue.async { [self] in
            isRunning = true
            reducer.beginSession(sessionID)
            let audio = CoreAudioSystemVolume(queue: queue)
            self.audio = audio
            guard audio.start(onChange: { [weak self] in self?.audioDidChange() }) else {
                publishStatus(.unavailable)
                audio.stop()
                self.audio = nil
                return
            }
            audioDidChange()
            installTap()
        }
    }

    func stop() {
        queue.async { [self] in
            isRunning = false
            tapGeneration &+= 1
            tapIsActive = false
            tap?.stop()
            tap = nil
            audio?.stop()
            audio = nil
            continuation.finish()
        }
    }

    func refreshPermissions() {
        queue.async { [weak self] in
            guard let self, isRunning, !isSuspended else { return }
            guard !tapIsActive || !AXIsProcessTrusted() else { return }
            installTap()
        }
    }

    func suspend() {
        queue.async { [weak self] in
            guard let self, isRunning, !isSuspended else { return }
            isSuspended = true
            tapGeneration &+= 1
            tapIsActive = false
            tap?.stop()
            tap = nil
            router = VolumeKeyRouter()
            publishCurrentStatus()
        }
    }

    func resume() {
        queue.async { [weak self] in
            guard let self, isRunning else { return }
            let needsInstall = isSuspended || !tapIsActive
            isSuspended = false
            // Audio listeners remain live during suspension so no stale volume
            // is replayed; a fresh tap is installed once per resumed session.
            if needsInstall { installTap() }
        }
    }

    private func installTap() {
        tapGeneration &+= 1
        tapIsActive = false
        router = VolumeKeyRouter()
        let currentTapGeneration = tapGeneration
        tap?.stop()
        tap = nil
        guard AXIsProcessTrusted() else {
            publishStatus(.permissionRequired)
            return
        }
        guard audio != nil else {
            publishStatus(.unavailable)
            return
        }
        let replacement = VolumeMediaKeyTap(
            keyHandler: { [weak self] key, eligible, fineStep in
                guard let self else { return false }
                return queue.sync {
                    guard isRunning, tapIsActive, tapGeneration == currentTapGeneration,
                          let audio else { return false }
                    let wasHandled = router.route(
                        key,
                        eligible  : eligible,
                        fineStep  : fineStep,
                        controller: audio
                    )
                    if key.isPressed, !(key.command == .toggleMute && key.isRepeat) {
                        audioDidChange(forcesFeedback: wasHandled)
                    }
                    return wasHandled
                }
            },
            availabilityHandler: { [weak self] isActive in
                guard let self else { return }
                queue.async { [weak self] in
                    guard let self, isRunning, tapGeneration == currentTapGeneration else { return }
                    tapIsActive = isActive
                    publishCurrentStatus()
                }
            }
        )
        tap = replacement
        replacement.start()
    }

    /// audioDidChange runs only on the AudioObject listener's registered queue.
    /// A baseline still advances while fallback is active, preventing replay.
    private func audioDidChange(forcesFeedback: Bool = false) {
        guard isRunning, let audio else { return }
        audio.refreshOutput()
        if let snapshot = audio.snapshot(),
           let event = reducer.receive(
               snapshot,
               sessionID   : sessionID,
               allowsNotice: tapIsActive && router.allowsObservedNotice,
               forcesFeedback: forcesFeedback
           ) {
            continuation.yield(.changed(event))
        }
        publishCurrentStatus()
    }

    private func publishCurrentStatus() {
        if !AXIsProcessTrusted() {
            publishStatus(.permissionRequired)
        } else if audio?.supportsVolume != true {
            publishStatus(.unsupportedOutput)
        } else {
            publishStatus(tapIsActive ? .active : .unavailable)
        }
    }

    private func publishStatus(_ status: VolumeMonitoringStatus) {
        guard status != lastStatus else { return }
        lastStatus = status
        logger.notice("Volume routing status: \(String(describing: status), privacy: .public)")
        continuation.yield(.status(status))
    }
}

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
