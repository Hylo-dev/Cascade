//
//  BluetoothAudioRouteMonitor.swift
//  Cascade
//

import AppKit
import CoreAudio
import Foundation

/// BluetoothAudioRouteMonitor reports a switch back to Bluetooth audio even
/// when its ACL link never disconnected. Starting, waking and session
/// activation establish silent baselines; there is no timer, enumeration, audio
/// write or device discovery.
@MainActor
final class BluetoothAudioRouteMonitor {

    private let workspaceCenter: NotificationCenter
    private let sourceFactory  : @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource

    private var worker    : BluetoothAudioRouteWorker?
    private var observers : [NSObjectProtocol] = []
    private var generation: UInt64             = 0

    init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        sourceFactory  : @escaping @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource = {
            CoreAudioBluetoothRouteSource(queue: $0)
        }
    ) {
        self.workspaceCenter = workspaceCenter
        self.sourceFactory   = sourceFactory
    }

    func start() -> AsyncStream<BluetoothConnectedDevice> {
        stop()

        generation &+= 1
        let currentGeneration = generation
        let pair = AsyncStream<BluetoothConnectedDevice>.makeStream(
            bufferingPolicy: .bufferingNewest(8)
        )
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, generation == currentGeneration else { return }
                stop()
            }
        }

        let worker = BluetoothAudioRouteWorker(
            sourceFactory: sourceFactory,
            continuation : pair.continuation
        )
        self.worker = worker

        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspaceCenter.addObserver(
                forName: name,
                object : nil,
                queue  : .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.worker?.suspend() }
            })
        }

        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspaceCenter.addObserver(
                forName: name,
                object : nil,
                queue  : .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.worker?.resume() }
            })
        }

        worker.start()
        return pair.stream
    }

    func stop() {
        generation &+= 1
        observers.forEach { workspaceCenter.removeObserver($0) }
        observers.removeAll()

        worker?.stop()
        worker = nil
    }

    isolated deinit {
        observers.forEach { workspaceCenter.removeObserver($0) }
        worker?.stop()
    }
}
