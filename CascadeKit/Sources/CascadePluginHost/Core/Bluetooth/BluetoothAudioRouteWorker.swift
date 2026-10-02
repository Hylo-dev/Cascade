//
//  BluetoothAudioRouteWorker.swift
//  CascadeKit
//

import Foundation
import os

/// BluetoothAudioRouteWorker reports a switch back to Bluetooth audio even when its link never
/// disconnected. Starting establishes a silent baseline; there is no timer, enumeration, audio
/// write or device discovery. It lives for one baseline of the Bluetooth source: the source
/// stops it before the Mac sleeps and starts a new one with every new baseline, and drops a route
/// that a stopped worker had already handed over.
///
/// Its HAL state is read and written only on its own queue, where the listener delivers too,
/// which is what makes the type safe to share. Epochs invalidate callbacks queued by a removed
/// registration.
final class BluetoothAudioRouteWorker: @unchecked Sendable {

    private let queue         = DispatchQueue(label: "cascade.plugin-host.bluetooth-route", qos: .utility)
    private let sourceFactory: @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource
    private let onRoute      : @Sendable (BluetoothConnectedDevice) -> Void
    private let logger        = Logger(subsystem: "hylo.Cascade", category: "BluetoothAudioRoute")

    private var source   : (any BluetoothAudioRouteSource)?
    private var reducer   = BluetoothAudioRouteReducer()
    private var epoch    : UInt64 = 0
    private var isRunning = false

    init(
        sourceFactory: @escaping @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource,
        onRoute      : @escaping @Sendable (BluetoothConnectedDevice) -> Void
    ) {
        self.sourceFactory = sourceFactory
        self.onRoute       = onRoute
    }

    func start() {
        queue.async { [self] in
            isRunning = true
            installSource()
        }
    }

    func stop() {
        queue.async { [self] in
            isRunning = false
            epoch &+= 1
            source?.stop()
            source = nil
        }
    }

    private func installSource() {
        epoch &+= 1
        let callbackEpoch = epoch
        let source        = sourceFactory(queue)
        self.source = source

        guard source.start(onChange: { [weak self] in
            guard let self else { return }

            // HAL drivers may invoke a callback reentrantly during registration.
            // Enqueue the read so the silent baseline always completes first.
            queue.async { [weak self] in self?.receive(epoch: callbackEpoch) }
        }) else {
            source.stop()
            self.source = nil
            isRunning   = false
            logger.error("Bluetooth audio route listener unavailable")
            return
        }

        reducer = BluetoothAudioRouteReducer()
        switch source.snapshot() {
            case .output(let snapshot): reducer.replaceBaseline(snapshot)
            case .noOutput:             reducer.replaceBaseline(nil)
            case .unavailable:          break // The first successful read will be the silent baseline.
        }
    }

    private func receive(epoch callbackEpoch: UInt64) {
        guard isRunning, callbackEpoch == epoch, let source else { return }

        let device: BluetoothConnectedDevice?
        switch source.snapshot() {
            case .output(let snapshot): device = reducer.receive(snapshot)
            case .noOutput:             device = reducer.receive(nil)
            case .unavailable:          return
        }

        if let device {
            onRoute(device)
        }
    }
}
