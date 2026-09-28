//
//  IOBluetoothConnectionMonitor.swift
//  Cascade
//

import AppKit
import IOBluetooth
import os

/// IOBluetoothConnectionMonitor publishes Classic Bluetooth connection
/// transitions without polling or starting device discovery.
///
/// Framework selectors terminate at a nonisolated observer because IOBluetooth
/// calls them on a private queue. Only copied Sendable values enter this
/// main-actor monitor, where the reducer and AsyncStream remain serialized.
@MainActor
final class IOBluetoothConnectionMonitor: NSObject, BluetoothMonitoring {

    private static let streamBufferLimit = 16

    private let registerForConnections: IOBluetoothConnectionRegistrar

    private(set) var status: BluetoothMonitoringStatus = .stopped

    private var notificationObserver: IOBluetoothConnectionObserver?
    private var wakeObserver        : NSObjectProtocol?
    private var continuation        : AsyncStream<BluetoothConnectionEvent>.Continuation?
    private let audioRouteMonitor    = BluetoothAudioRouteMonitor()
    private var audioRouteTask      : Task<Void, Never>?
    private var baselineTask        : Task<Void, Never>?

    private static let baselineQueue = DispatchQueue(label: "hylo.Cascade.bluetooth-baseline", qos: .utility)
    private let logger               = Logger(subsystem: "hylo.Cascade", category: "BluetoothMonitor")

    private let metadataEnricher = BluetoothMetadataEnricher()
    private var nextEventID      = UInt64.zero
    private var reducer          = BluetoothConnectionReducer()
    private var callbackGate     = BluetoothConnectionCallbackGate()
    private var sessionID        = UInt64.zero
    private var isRunning        = false

    /// init accepts the global registration boundary so an unavailable
    /// IOBluetooth service can be verified without fabricating device events.
    init(
        registerForConnections: @escaping IOBluetoothConnectionRegistrar = { observer, selector in
            IOBluetoothDevice.register(
                forConnectNotifications: observer,
                selector               : selector
            )
        }
    ) {
        self.registerForConnections = registerForConnections
    }

    /// start replaces any prior monitoring session and returns its bounded
    /// event stream. Existing connected devices become a silent baseline.
    func start() -> AsyncStream<BluetoothConnectionEvent> {
        stop()

        sessionID &+= 1
        callbackGate.beginSession(sessionID: sessionID)

        let currentSessionID = sessionID
        let streamPair       = AsyncStream<BluetoothConnectionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.streamBufferLimit)
        )

        continuation = streamPair.continuation
        streamPair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == currentSessionID else { return }

                self.stop()
            }
        }

        let notificationObserver = IOBluetoothConnectionObserver(
            sessionID             : currentSessionID,
            registerForConnections: registerForConnections,
            callbackHandler       : { [weak self] callback in
                Task { @MainActor [weak self] in
                    self?.receive(callback)
                }
            }
        )

        guard notificationObserver.start() else {
            sessionID &+= 1
            continuation = nil
            streamPair.continuation.finish()
            status = .unavailable("IOBluetooth connection notifications are unavailable.")
            return streamPair.stream
        }

        self.notificationObserver = notificationObserver

        isRunning = true
        status    = .monitoring

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object : nil,
            queue  : .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.workspaceDidWake(sessionID: currentSessionID)
            }
        }

        rebuildBaseline()

        return streamPair.stream
    }

    /// stop tears down the active stream and every framework registration.
    /// Calling it repeatedly is safe and leaves no wake observer behind.
    func stop() {
        sessionID &+= 1
        callbackGate.beginSession(sessionID: sessionID)
        isRunning = false
        status    = .stopped

        metadataEnricher.cancelAll()
        baselineTask?.cancel()
        baselineTask = nil
        audioRouteTask?.cancel()
        audioRouteTask = nil
        audioRouteMonitor.stop()
        notificationObserver?.stop()
        notificationObserver = nil

        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil

        let activeContinuation = continuation
        continuation = nil
        activeContinuation?.finish()

        reducer = BluetoothConnectionReducer()
    }

    isolated deinit {
        baselineTask?.cancel()
        audioRouteTask?.cancel()
        audioRouteMonitor.stop()
        metadataEnricher.cancelAll()
        notificationObserver?.stop()

        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }

        continuation?.finish()
    }

    /// receive accepts copied callback values only for the active session.
    /// This guard makes already-enqueued callbacks inert across stop/restart.
    private func receive(_ callback: IOBluetoothConnectionCallback) {
        guard isRunning else { return }

        switch callback {
            case .connected(let identity, let device):
                guard callbackGate.accepts(identity),
                      let event = reducer.recordConnection(
                          device,
                          eventID: nextEventID &+ 1
                      )
                else { return }

                nextEventID &+= 1
                publishConnection(event, identity: identity)

            case .disconnected(let identity, let deviceID):
                guard callbackGate.accepts(identity),
                      let event = reducer.recordDisconnection(
                          deviceID: deviceID,
                          eventID : nextEventID &+ 1
                      )
                else { return }

                nextEventID &+= 1
                metadataEnricher.cancel(deviceID: deviceID)
                continuation?.yield(event)
        }
    }

    private func receiveAudioRoute(
        _ device: BluetoothConnectedDevice,
        identity: BluetoothConnectionCallbackIdentity
    ) {
        guard let event = reducer.recordAudioRoute(device, eventID: nextEventID &+ 1) else { return }

        nextEventID &+= 1
        publishConnection(event, identity: identity)
    }

    private func publishConnection(
        _ event : BluetoothConnectionEvent,
        identity: BluetoothConnectionCallbackIdentity
    ) {
        logger.info("Bluetooth notice event: \(event.kind == .audioRoute ? "audio-route" : "connection", privacy: .public)")
        continuation?.yield(event)

        metadataEnricher.enrich(deviceID: event.deviceID) { [weak self] metadata in
            guard let self,
                  self.isRunning,
                  self.callbackGate.accepts(identity),
                  let update = self.reducer.enrichConnection(
                      deviceID: event.deviceID,
                      eventID : event.eventID,
                      metadata: metadata
                  )
            else { return }

            self.continuation?.yield(update)
        }
    }

    /// workspaceDidWake reconciles the current connections as a new silent
    /// baseline because IOBluetooth callbacks may be stale or absent over sleep.
    private func workspaceDidWake(sessionID callbackSessionID: UInt64) {
        guard isRunning, callbackSessionID == sessionID else { return }

        rebuildBaseline()
    }

    /// rebuildBaseline enumerates cached paired and recent devices only, on a
    /// utility queue: each call is a synchronous bluetoothd round trip and the
    /// first one initializes IOBluetooth, which would stall launch and wake on
    /// the main thread. Transitions that race it are held by the observer and
    /// replayed after the baseline, preserving the synchronous ordering.
    private func rebuildBaseline() {
        guard let notificationObserver else { return }

        metadataEnricher.cancelAll()
        let baselineEpoch = notificationObserver.beginBaselineReplacement()
        callbackGate.replaceBaseline(epoch: baselineEpoch)
        let identity = callbackGate.identity

        baselineTask?.cancel()
        baselineTask = Task { [weak self] in
            let snapshots = await withCheckedContinuation { continuation in
                Self.baselineQueue.async {
                    let connectedDevices = IOBluetoothDeviceSnapshot.connectedDevices()
                    notificationObserver.replaceObservedDevices(connectedDevices)
                    continuation.resume(
                        returning: connectedDevices.compactMap(IOBluetoothDeviceSnapshot.make(from:))
                    )
                }
            }
            guard !Task.isCancelled,
                  let self,
                  self.isRunning,
                  self.callbackGate.accepts(identity)
            else { return }

            self.reducer.replaceBaseline(with: snapshots)
            self.restartAudioRouteMonitoring()
            for callback in notificationObserver.finishBaselineReplacement() {
                self.receive(callback)
            }
        }
    }

    /// Replacing the ACL baseline must discard buffered route events too.
    /// Capturing its identity prevents a pre-wake stream value from acquiring
    /// the new epoch merely because the main actor consumes it after wake.
    private func restartAudioRouteMonitoring() {
        audioRouteTask?.cancel()

        let identity    = callbackGate.identity
        let routeStream = audioRouteMonitor.start()
        audioRouteTask = Task { [weak self] in
            for await device in routeStream {
                guard !Task.isCancelled,
                      let self,
                      self.isRunning,
                      self.callbackGate.accepts(identity)
                else { return }

                self.receiveAudioRoute(device, identity: identity)
            }
        }
    }
}
