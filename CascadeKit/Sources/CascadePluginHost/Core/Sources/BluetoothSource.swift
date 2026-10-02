//
//  BluetoothSource.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import IOBluetooth
import os

/// BluetoothSource is the `bluetooth` catalog source: Classic Bluetooth links that connect or
/// disconnect, and audio that comes back to a Bluetooth output whose link never dropped, each
/// numbered and then revised once the device reports its battery and identity. It never polls
/// and never starts discovery: it waits on IOBluetooth's connection notifications, the HAL's
/// output listener and IOKit's system power messages.
///
/// Starting it emits a baseline, event zero, that says whether monitoring works; the devices
/// connected at that moment are state, not news. A wake rebuilds that baseline silently, since
/// callbacks may be stale or missing across sleep, and sleep stops the route listener until then.
/// Event numbers keep counting across a stop and a start, so they never repeat within one
/// PluginHost and a plugin can tell a newer event from a late reading of an older one. Unlike
/// Cascade's old monitor, it does not pause while the user's session is switched out: an inactive
/// session cannot see the notch, and the notice it might raise there expires on its own.
///
/// IOBluetooth delivers connection notifications through the run loop of the thread that
/// registered, so the observer is started and stopped on the main queue, which PluginHost's main
/// run loop services (`RunLoopType = NSRunLoop`). Everything else lives on the source's serial
/// queue: every stored property below is read and written only there, which is what makes the
/// type safe to share; `start` and `stop` reach it with `queue.async` from the XPC threads, so a
/// slow read of bluetoothd on this queue never holds up PluginHost's connection.
public final class BluetoothSource: PluginCatalogSource, @unchecked Sendable {

    typealias ObserverFactory = @Sendable (UInt64, @escaping @Sendable (IOBluetoothConnectionCallback) -> Void) -> any BluetoothConnectionObserving

    private let queue              = DispatchQueue(label: "cascade.plugin-host.bluetooth", qos: .utility)
    private let makeObserver      : ObserverFactory
    private let routeSourceFactory: @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource
    private let registrationQueue : DispatchQueue
    private let enricher          : BluetoothMetadataEnricher
    private let logger             = Logger(subsystem: "hylo.Cascade", category: "BluetoothSource")

    private var emit           : (@Sendable (PluginSourceEvent) -> Void)?
    private var observer       : (any BluetoothConnectionObserving)?
    private var routeWorker    : BluetoothAudioRouteWorker?
    private var power          : SystemPowerNotifications?
    private var reducer         = BluetoothConnectionReducer()
    private var gate            = BluetoothConnectionCallbackGate()
    private var sessionID       = UInt64.zero
    private var routeGeneration = UInt64.zero
    private var nextEventID     = UInt64.zero
    private var isRunning       = false

    public convenience init() {
        self.init(
            makeObserver      : { sessionID, handler in
                IOBluetoothConnectionObserver(
                    sessionID             : sessionID,
                    registerForConnections: { observer, selector in
                        IOBluetoothDevice.register(forConnectNotifications: observer, selector: selector)
                    },
                    callbackHandler       : handler
                )
            },
            metadataReader    : SystemBluetoothDeviceMetadataReader(),
            routeSourceFactory: { CoreAudioBluetoothRouteSource(queue: $0) }
        )
    }

    init(
        makeObserver      : @escaping ObserverFactory,
        metadataReader    : any BluetoothDeviceMetadataReading,
        routeSourceFactory: @escaping @Sendable (DispatchQueue) -> any BluetoothAudioRouteSource,
        registrationQueue : DispatchQueue = .main,
        metadataRetryDelay: DispatchTimeInterval = .seconds(1)
    ) {
        self.makeObserver       = makeObserver
        self.routeSourceFactory = routeSourceFactory
        self.registrationQueue  = registrationQueue
        self.enricher           = BluetoothMetadataEnricher(reader: metadataReader, queue: queue, retryDelay: metadataRetryDelay)
    }

    public func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void) {
        queue.async { [self] in
            tearDown()

            sessionID &+= 1
            gate.beginSession(sessionID: sessionID)
            self.emit = emit

            let session  = sessionID
            let observer = makeObserver(session) { [weak self] callback in
                self?.queue.async { [weak self] in self?.receive(callback) }
            }
            self.observer = observer

            registrationQueue.async { [weak self] in
                let isRegistered = observer.start()

                self?.queue.async { [weak self] in
                    self?.didRegister(session: session, isRegistered: isRegistered)
                }
            }
        }
    }

    public func stop() {
        queue.async { [self] in
            tearDown()
        }
    }

    /// simulate delivers a power transition as IOKit would; tests drive the source with it.
    func simulate(_ transition: SystemPowerNotifications.Transition) {
        queue.sync {
            receive(transition)
        }
    }

    /// didRegister finishes a start once the observer knows whether IOBluetooth accepted it. A
    /// start or a stop that came meanwhile has already queued this observer's stop after its
    /// start on the registration queue, so a stale answer is simply dropped.
    private func didRegister(
        session     : UInt64,
        isRegistered: Bool
    ) {
        guard session == sessionID, emit != nil else { return }

        guard isRegistered else {
            observer = nil
            logger.error("IOBluetooth connection notifications are unavailable")
            publish(.baseline(isAvailable: false))
            return
        }

        isRunning = true
        power     = SystemPowerNotifications { [weak self] transition in
            self?.queue.async { [weak self] in self?.receive(transition) }
        }
        publish(.baseline(isAvailable: true))
        rebuildBaseline()
    }

    private func tearDown() {
        sessionID &+= 1
        gate.beginSession(sessionID: sessionID)
        isRunning = false
        emit      = nil

        enricher.cancelAll()
        stopRouteMonitoring()
        power?.stop()
        power = nil

        if let observer {
            registrationQueue.async { observer.stop() }
        }
        observer = nil
        reducer  = BluetoothConnectionReducer()
    }

    private func receive(_ transition: SystemPowerNotifications.Transition) {
        guard isRunning else { return }

        switch transition {
            case .willSleep:
                stopRouteMonitoring()

            case .didWake:
                rebuildBaseline()
        }
    }

    /// receive accepts copied callback values only for the active session and baseline. This
    /// guard makes already-enqueued callbacks inert across stop, restart and wake.
    private func receive(_ callback: IOBluetoothConnectionCallback) {
        guard isRunning else { return }

        switch callback {
            case .connected(let identity, let device):
                guard gate.accepts(identity),
                      let event = reducer.recordConnection(device, eventID: nextEventID &+ 1)
                else { return }

                nextEventID &+= 1
                publishConnection(event, identity: identity)

            case .disconnected(let identity, let deviceID):
                guard gate.accepts(identity),
                      let event = reducer.recordDisconnection(deviceID: deviceID, eventID: nextEventID &+ 1)
                else { return }

                nextEventID &+= 1
                enricher.cancel(deviceID: deviceID)
                publish(event)
        }
    }

    private func receiveRoute(
        _ device  : BluetoothConnectedDevice,
        identity  : BluetoothConnectionCallbackIdentity,
        generation: UInt64
    ) {
        guard isRunning,
              generation == routeGeneration,
              gate.accepts(identity),
              let event = reducer.recordAudioRoute(device, eventID: nextEventID &+ 1)
        else { return }

        nextEventID &+= 1
        publishConnection(event, identity: identity)
    }

    /// publishConnection publishes a new event and reads the device's metadata, which revises
    /// that event only while it is still the device's current one.
    private func publishConnection(
        _ event : BluetoothConnectionEvent,
        identity: BluetoothConnectionCallbackIdentity
    ) {
        publish(event)

        enricher.enrich(deviceID: event.deviceID) { [weak self] metadata in
            guard let self,
                  isRunning,
                  gate.accepts(identity),
                  let update = reducer.enrichConnection(deviceID: event.deviceID, eventID: event.eventID, metadata: metadata)
            else { return }

            publish(update)
        }
    }

    /// rebuildBaseline reads the devices connected now as silent state. Callbacks queued before
    /// it belong to the old baseline and are rejected; those that race it are held by the
    /// observer and replayed after it, preserving their order.
    private func rebuildBaseline() {
        guard let observer else { return }

        enricher.cancelAll()
        gate.replaceBaseline(epoch: observer.beginBaselineReplacement())
        reducer.replaceBaseline(with: observer.connectedDevices())
        restartRouteMonitoring()

        for callback in observer.finishBaselineReplacement() {
            receive(callback)
        }
    }

    /// restartRouteMonitoring starts a new route listener for the current baseline. A route the
    /// previous listener had already handed over carries an old generation and is dropped.
    private func restartRouteMonitoring() {
        stopRouteMonitoring()

        let identity   = gate.identity
        let generation = routeGeneration
        let worker     = BluetoothAudioRouteWorker(sourceFactory: routeSourceFactory) { [weak self] device in
            self?.queue.async { [weak self] in
                self?.receiveRoute(device, identity: identity, generation: generation)
            }
        }
        routeWorker = worker
        worker.start()
    }

    private func stopRouteMonitoring() {
        routeGeneration &+= 1
        routeWorker?.stop()
        routeWorker = nil
    }

    private func publish(_ event: BluetoothConnectionEvent) {
        publish(
            PluginBluetoothState(
                deviceID   : event.deviceID,
                name       : event.name,
                symbolName : event.symbolName,
                isConnected: event.isConnected,
                battery    : event.battery.map {
                    PluginBluetoothBattery(level: $0.level, left: $0.left, right: $0.right, caseLevel: $0.caseLevel)
                },
                model      : event.model,
                productID  : event.productID,
                colorID    : event.colorID,
                eventID    : event.eventID,
                revision   : event.revision,
                kind       : event.kind,
                isAvailable: true
            )
        )
    }

    private func publish(_ state: PluginBluetoothState) {
        guard let emit, let event = try? state.event() else { return }

        emit(event)
    }
}
