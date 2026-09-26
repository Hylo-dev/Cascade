//
//  BluetoothAudioRouteMonitor.swift
//  Cascade
//

import AppKit
import CoreAudio
import notify
import Foundation
import os

/// A transient HAL read error must not look like a physical route departure.
nonisolated enum BluetoothAudioRouteReadResult: Equatable, Sendable {
    case output(BluetoothAudioRouteSnapshot)
    case noOutput
    case unavailable
}

/// Every source operation runs on the worker's serial queue. Only immutable
/// snapshots cross that boundary; implementations must never start discovery.
nonisolated protocol BluetoothAudioRouteSource: AnyObject {
    func start(onChange: @escaping @Sendable () -> Void) -> Bool
    func snapshot() -> BluetoothAudioRouteReadResult
    func stop()
}

/// Public HAL listener plus a read-only Smart Routing notification hint. The
/// Darwin notification carries no identity: it can only trigger the same HAL
/// snapshot and cannot manufacture a connection when the output is unchanged.
nonisolated private final class CoreAudioBluetoothRouteSource: BluetoothAudioRouteSource {
    private let queue: DispatchQueue
    private var listener: AudioObjectPropertyListenerBlock?
    private var routingToken: Int32?

    init(queue: DispatchQueue) { self.queue = queue }

    func start(onChange: @escaping @Sendable () -> Void) -> Bool {
        stop()
        var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        let listener: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        guard AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, listener
        ) == noErr else { return false }
        self.listener = listener
        var token: Int32 = 0
        if notify_register_dispatch("com.apple.BluetoothServices.AudioRoutingChanged", &token, queue, { _ in
            onChange()
        }) == NOTIFY_STATUS_OK {
            routingToken = token
        }
        return true
    }

    func snapshot() -> BluetoothAudioRouteReadResult {
        guard let deviceID = readUInt32(
            AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDefaultOutputDevice
        ) else { return .unavailable }
        guard deviceID != kAudioObjectUnknown else { return .noOutput }
        guard let uid = readString(deviceID, selector: kAudioDevicePropertyDeviceUID),
              let transport = readUInt32(deviceID, selector: kAudioDevicePropertyTransportType) else { return .unavailable }
        let name = readString(deviceID, selector: kAudioObjectPropertyName) ?? "Bluetooth Device"
        return .output(BluetoothAudioRouteSnapshot(uid: uid, name: name, transportType: transport))
    }

    func stop() {
        if let listener {
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, listener
            )
            self.listener = nil
        }
        if let routingToken { notify_cancel(routingToken) }
        routingToken = nil
    }

    private func readUInt32(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> UInt32? {
        var address = Self.address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, &value) == noErr,
              size == MemoryLayout<UInt32>.size else { return nil }
        return value
    }

    private func readString(_ objectID: AudioObjectID, selector: AudioObjectPropertySelector) -> String? {
        var address = Self.address(selector)
        // HAL's UID/name CFString properties transfer ownership to the caller.
        let storage = UnsafeMutablePointer<Unmanaged<CFString>?>.allocate(capacity: 1)
        storage.initialize(to: nil)
        defer { storage.deinitialize(count: 1); storage.deallocate() }
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, storage) == noErr,
              let value = storage.pointee?.takeRetainedValue() else { return nil }
        return value as String
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain
        )
    }
}

/// Mutable HAL state stays on one queue. Epochs invalidate callbacks queued by
/// a removed registration; the lock synchronously invalidates publication at stop.
nonisolated private final class BluetoothAudioRouteWorker: @unchecked Sendable {
    private let queue = DispatchQueue(label: "Cascade.BluetoothAudioRoute", qos: .utility)
    private let sourceFactory: @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource
    private let continuation: AsyncStream<BluetoothConnectedDevice>.Continuation
    private let publicationLock = NSLock()
    private var acceptsPublication = true
    private var source: (any BluetoothAudioRouteSource)?
    private var reducer = BluetoothAudioRouteReducer()
    private var epoch: UInt64 = 0
    private var isRunning = false
    private var isSuspended = false
    private let logger = Logger(subsystem: "hylo.Cascade", category: "BluetoothAudioRoute")

    init(
        sourceFactory: @escaping @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource,
        continuation: AsyncStream<BluetoothConnectedDevice>.Continuation
    ) {
        self.sourceFactory = sourceFactory
        self.continuation = continuation
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
        let source = sourceFactory(queue)
        self.source = source
        guard source.start(onChange: { [weak self] in
            guard let self else { return }
            // HAL drivers may invoke a callback reentrantly during registration.
            // Enqueue the read so the silent baseline always completes first.
            queue.async { [weak self] in self?.receive(epoch: callbackEpoch) }
        }) else {
            source.stop()
            self.source = nil
            isRunning = false
            continuation.finish()
            logger.error("Bluetooth audio route listener unavailable")
            return
        }
        reducer = BluetoothAudioRouteReducer()
        switch source.snapshot() {
        case .output(let snapshot): reducer.replaceBaseline(snapshot)
        case .noOutput: reducer.replaceBaseline(nil)
        case .unavailable: break // The first successful read will be the silent baseline.
        }
    }

    private func receive(epoch callbackEpoch: UInt64) {
        guard isRunning, !isSuspended, callbackEpoch == epoch,
              publicationLock.withLock({ acceptsPublication }), let source else { return }
        let device: BluetoothConnectedDevice?
        switch source.snapshot() {
        case .output(let snapshot): device = reducer.receive(snapshot)
        case .noOutput: device = reducer.receive(nil)
        case .unavailable: return
        }
        guard let device else { return }
        publicationLock.withLock {
            guard acceptsPublication else { return }
            continuation.yield(device)
        }
    }
}

/// Reports a switch back to Bluetooth audio even when its ACL link never
/// disconnected. Starting, waking and session activation establish silent
/// baselines; there is no timer, enumeration, audio write or device discovery.
@MainActor
final class BluetoothAudioRouteMonitor {
    private let workspaceCenter: NotificationCenter
    private let sourceFactory: @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource
    private var worker: BluetoothAudioRouteWorker?
    private var observers: [NSObjectProtocol] = []
    private var generation: UInt64 = 0

    init(
        workspaceCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
        sourceFactory: @escaping @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource = {
            CoreAudioBluetoothRouteSource(queue: $0)
        }
    ) {
        self.workspaceCenter = workspaceCenter
        self.sourceFactory = sourceFactory
    }

    func start() -> AsyncStream<BluetoothConnectedDevice> {
        stop()
        generation &+= 1
        let currentGeneration = generation
        let pair = AsyncStream<BluetoothConnectedDevice>.makeStream(bufferingPolicy: .bufferingNewest(8))
        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, generation == currentGeneration else { return }
                stop()
            }
        }
        let worker = BluetoothAudioRouteWorker(sourceFactory: sourceFactory, continuation: pair.continuation)
        self.worker = worker
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.worker?.suspend() }
            })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
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
