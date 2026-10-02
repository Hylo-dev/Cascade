//
//  CoreAudioVolumeMonitor.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// CoreAudioVolumeMonitor owns one stream generation at a time. Cancellation,
/// disable and deinitialization release listeners and the Quartz tap. The
/// observers only the tap needs run only while a session runs and may route
/// keys; the level is observed without them.
@MainActor
final class CoreAudioVolumeMonitor: VolumeMonitoring {

    private var worker   : VolumeMonitorWorker?
    private var sessionID: UInt64 = 0

    private let tapObservers = VolumeTapObservers()

    var routesKeys = true {
        didSet {
            guard routesKeys != oldValue else { return }

            worker?.setRoutesKeys(routesKeys)
            updateTapObservers()
        }
    }

    func start() -> AsyncStream<VolumeMonitorUpdate> {
        stop()
        sessionID &+= 1

        let currentSession = sessionID
        let pair           = AsyncStream<VolumeMonitorUpdate>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, sessionID == currentSession else { return }

                stop()
            }
        }

        let worker = VolumeMonitorWorker(
            sessionID   : currentSession,
            routesKeys  : routesKeys,
            continuation: pair.continuation
        )
        self.worker = worker
        updateTapObservers()
        worker.start()
        return pair.stream
    }

    func stop() {
        sessionID &+= 1
        worker?.stop()
        worker = nil
        updateTapObservers()
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

    /// updateTapObservers runs the tap's observers while a session may route
    /// keys and stops them otherwise.
    private func updateTapObservers() {
        guard worker != nil, routesKeys else {
            tapObservers.stop()
            return
        }
        guard !tapObservers.isObserving else { return }

        tapObservers.start(
            refresh: { [weak self] in self?.refreshPermissions() },
            suspend: { [weak self] in self?.worker?.suspend() },
            resume : { [weak self] in self?.worker?.resume() }
        )
    }

    isolated deinit {
        tapObservers.stop()
        worker?.stop()
    }
}
