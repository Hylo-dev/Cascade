//
//  VolumePluginSource.swift
//  Cascade
//

import CascadeContracts
import CascadePluginEngine
import Foundation

/// VolumePluginSource is the `volume` catalog source, run in the kernel beside the volume key tap
/// because the two are one subsystem: the tap decides which changes replace the system HUD, falls
/// silent when it forwards a key to macOS and forces feedback on a handled key at the limit. The
/// source emits a baseline when it starts, then every change the monitor announced, numbered, and
/// stops the monitor, and with it the tap, when the plugin releases it.
///
/// The engine calls it on its own queue; everything here runs on the main actor, reached through
/// the main queue so a start and the stop that follows it keep their order.
@MainActor
final class VolumePluginSource: PluginEventSource {

    /// statusHandler receives the monitor's routing status, for Cascade's settings.
    var statusHandler: (VolumeMonitoringStatus) -> Void = { _ in }

    let monitor: any VolumeMonitoring

    private var task: Task<Void, Never>?

    init(monitor: any VolumeMonitoring) {
        self.monitor = monitor
    }

    nonisolated func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.begin(emit) }
        }
    }

    nonisolated func stop() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    private func begin(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void) {
        end()
        statusHandler(.starting)
        if let baseline = try? PluginVolumeState(percentage: nil, isMuted: false, announcement: 0).event() {
            emit(baseline)
        }

        let stream = monitor.start()
        task = Task { [weak self] in
            for await update in stream {
                guard let self, !Task.isCancelled else { return }

                switch update {
                    case .status(let status):
                        statusHandler(status)

                    case .changed(let change):
                        let state = PluginVolumeState(percentage: change.percentage, isMuted: change.isMuted, announcement: change.revision)
                        if let event = try? state.event() {
                            emit(event)
                        }
                }
            }
        }
    }

    private func end() {
        guard let task else { return }

        task.cancel()
        self.task = nil
        monitor.stop()
        statusHandler(.stopped)
    }
}
