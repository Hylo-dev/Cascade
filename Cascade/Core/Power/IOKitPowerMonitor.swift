//
//  IOKitPowerMonitor.swift
//  Cascade
//

import AppKit
import IOKit.ps
import os

/// IOKit and Low Power Mode notifications are the only wakeups. A serial
/// utility queue preserves sample order; session checks discard late results.
@MainActor
final class IOKitPowerMonitor: PowerMonitoring {

    private let reader: any MacPowerReading
    private let queue  = DispatchQueue(label: "Cascade.Power", qos: .utility)
    private let logger = Logger(subsystem: "hylo.Cascade", category: "Power")

    private var source            : CFRunLoopSource?
    private var powerObserver     : NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var continuation      : AsyncStream<PowerConnectionUpdate>.Continuation?

    private var reducer     = PowerConnectionReducer()
    private var generation : UInt64 = 0
    private var sampleEpoch: UInt64 = 0
    private var isSleeping  = false

    init(reader: any MacPowerReading = SystemMacPowerReader()) {
        self.reader = reader
    }

    func start() -> AsyncStream<PowerConnectionUpdate> {
        stop()

        let session = generation
        let pair    = AsyncStream<PowerConnectionUpdate>.makeStream()
        continuation = pair.continuation
        guard let source = IOPSNotificationCreateRunLoopSource(
            { context in IOKitPowerMonitor.powerChanged(context) },
            Unmanaged.passUnretained(self).toOpaque()
        )?.takeRetainedValue()
        else {
            logger.error("Could not register power source notifications")
            pair.continuation.finish()
            continuation = nil
            return pair.stream
        }

        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)

        powerObserver = NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object : nil,
            queue  : .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }

        let workspace = NSWorkspace.shared.notificationCenter
        workspaceObservers = [
            workspace.addObserver(
                forName: NSWorkspace.willSleepNotification,
                object : nil,
                queue  : .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }

                    self.isSleeping = true
                    self.sampleEpoch &+= 1
                    self.reducer = PowerConnectionReducer()
                }
            },
            workspace.addObserver(
                forName: NSWorkspace.didWakeNotification,
                object : nil,
                queue  : .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isSleeping = false
                    self?.sample()
                }
            }
        ]

        pair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.generation == session else { return }

                self.stop()
            }
        }

        sample()
        return pair.stream
    }

    func stop() {
        generation &+= 1

        if let source {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            CFRunLoopSourceInvalidate(source)
        }
        source = nil

        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
        powerObserver = nil

        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()

        continuation?.finish()
        continuation = nil

        reducer    = PowerConnectionReducer()
        isSleeping = false
    }

    /// The unretained context is valid only while our source is registered on
    /// the main run loop. stop/deinit invalidate it on that same actor first.
    private nonisolated static func powerChanged(_ context: UnsafeMutableRawPointer?) {
        guard let context else { return }

        let monitor = Unmanaged<IOKitPowerMonitor>.fromOpaque(context).takeUnretainedValue()
        MainActor.assumeIsolated {
            monitor.sample()
        }
    }

    private func sample() {
        guard continuation != nil, !isSleeping else { return }

        let session = generation
        let epoch   = sampleEpoch
        let reader  = reader

        queue.async { [weak self] in
            let snapshot = reader.read()
            Task { @MainActor [weak self] in
                guard let self,
                      self.generation == session,
                      self.sampleEpoch == epoch
                else { return }

                if let update = self.reducer.receive(snapshot) {
                    self.continuation?.yield(update)
                }
            }
        }
    }

    isolated deinit {
        if let source { CFRunLoopSourceInvalidate(source) }
        if let powerObserver { NotificationCenter.default.removeObserver(powerObserver) }
        for observer in workspaceObservers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        continuation?.finish()
    }
}
