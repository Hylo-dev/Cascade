//
//  BluetoothAudioRouteWorker.swift
//  Cascade
//

import AppKit
import CoreAudio
import Foundation
import os

/// Mutable HAL state stays on one queue. Epochs invalidate callbacks queued by
/// a removed registration; the lock synchronously invalidates publication at stop.
nonisolated final class BluetoothAudioRouteWorker: @unchecked Sendable {

    private let queue           = DispatchQueue(label: "Cascade.BluetoothAudioRoute", qos: .utility)
    private let sourceFactory  : @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource
    private let continuation   : AsyncStream<BluetoothConnectedDevice>.Continuation
    private let publicationLock = NSLock()

    private var acceptsPublication = true
    private var source            : (any BluetoothAudioRouteSource)?
    private var reducer            = BluetoothAudioRouteReducer()
    private var epoch             : UInt64 = 0
    private var isRunning          = false
    private var isSuspended        = false

    private let logger = Logger(subsystem: "hylo.Cascade", category: "BluetoothAudioRoute")

    init(
        sourceFactory: @escaping @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource,
        continuation : AsyncStream<BluetoothConnectedDevice>.Continuation
    ) {
        self.sourceFactory = sourceFactory
        self.continuation  = continuation
    }

    func start() {
        queue.async { [self] in
            guard publicationLock.withLock({ acceptsPublication }) else { return }

            isRunning = true
            installSource()
        }
    }

    func stop() {
        publicationLock.withLock { acceptsPublication = false }

        queue.async { [self] in
            isRunning = false
            epoch &+= 1
            source?.stop()
            source = nil
            continuation.finish()
        }
    }

    func suspend() {
        queue.async { [self] in
            guard isRunning, !isSuspended else { return }

            isSuspended = true
            epoch &+= 1
            source?.stop()
            source = nil
        }
    }

    func resume() {
        queue.async { [self] in
            guard isRunning else { return }

            isSuspended = false

            // A wake can arrive without a matching sleep callback (for example
            // after observer registration). Always replace the silent baseline.
            source?.stop()
            source = nil
            installSource()
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
            continuation.finish()
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
        guard isRunning,
              !isSuspended,
              callbackEpoch == epoch,
              publicationLock.withLock({ acceptsPublication }),
              let source
        else { return }

        let device: BluetoothConnectedDevice?
        switch source.snapshot() {
            case .output(let snapshot): device = reducer.receive(snapshot)
            case .noOutput:             device = reducer.receive(nil)
            case .unavailable:          return
        }
        guard let device else { return }

        publicationLock.withLock {
            guard acceptsPublication else { return }
            continuation.yield(device)
        }
    }
}
