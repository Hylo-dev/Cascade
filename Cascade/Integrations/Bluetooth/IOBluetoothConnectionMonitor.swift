//
//  IOBluetoothConnectionMonitor.swift
//  Cascade
//

import AppKit
import IOBluetooth
import os

typealias IOBluetoothConnectionRegistrar = @Sendable (AnyObject, Selector) -> IOBluetoothUserNotification?

/// IOBluetoothConnectionCallback carries a framework callback across to the
/// main actor without retaining or sending an `IOBluetoothDevice`.
nonisolated private enum IOBluetoothConnectionCallback: Sendable {
    case connected(
        identity: BluetoothConnectionCallbackIdentity,
        device  : BluetoothConnectedDevice
    )
    case disconnected(
        identity: BluetoothConnectionCallbackIdentity,
        deviceID: String
    )
}

/// IOBluetoothDeviceSnapshot copies the small public metadata set used by the
/// activity before the framework-owned device leaves its callback queue.
nonisolated private enum IOBluetoothDeviceSnapshot {

    static func make(
        from device: IOBluetoothDevice
    ) -> BluetoothConnectedDevice? {

        guard let deviceID = stableIdentifier(for: device) else { return nil }
        return BluetoothConnectedDevice(
            deviceID   : deviceID,
            name       : device.name ?? device.nameOrAddress ?? "Bluetooth Device",
            symbolName : symbolName(for: device)
        )
    }

    /// connectedDevices combines the framework's cached paired and recent
    /// lists because either list alone can omit a valid Classic device. Every
    /// call is a synchronous bluetoothd round trip, so it runs off the main
    /// actor; these APIs read existing records and never start discovery.
    static func connectedDevices() -> [IOBluetoothDevice] {

        let pairedDevices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []
        let recentDevices = IOBluetoothDevice.recentDevices(0) as? [IOBluetoothDevice] ?? []
        var devicesByID   : [String: IOBluetoothDevice] = [:]

        for device in pairedDevices + recentDevices where device.isConnected() {
            guard let deviceID = stableIdentifier(for: device) else { continue }
            devicesByID[deviceID] = device
        }

        return Array(devicesByID.values)
    }

    static func stableIdentifier(
        for device: IOBluetoothDevice
    ) -> String? {
        // IOBluetooth declares this as an IUO, but disconnect can clear its cache
        // before the callback arrives. A missing identity must never be force-unwrapped.
        guard let address = device.addressString,
              BluetoothMetadataParser.normalizedAddress(address) != nil else { return nil }
        return address.uppercased()
    }

    /// symbolName maps the public Bluetooth class-of-device category to a
    /// conservative SF Symbol without claiming a model the framework omitted.
    private static func symbolName(
        for device: IOBluetoothDevice
    ) -> String {

        switch device.deviceClassMajor {
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorAudio):
            switch device.deviceClassMinor {
            case BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioHeadset),
                 BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioHandsFree),
                 BluetoothDeviceClassMinor(kBluetoothDeviceClassMinorAudioHeadphones):
                return "headphones"
            default:
                return "speaker.wave.2"
            }
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorComputer):
            return "desktopcomputer"
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPhone):
            return "smartphone"
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorPeripheral):
            let peripheralKind = device.deviceClassMinor & 0x30

            if peripheralKind == kBluetoothDeviceClassMinorPeripheral1Keyboard {
                return "keyboard"
            }

            if peripheralKind == kBluetoothDeviceClassMinorPeripheral1Pointing {
                return "computermouse"
            }

            return "gamecontroller"
        case BluetoothDeviceClassMajor(kBluetoothDeviceClassMajorImaging):
            return "camera"
        default:
            return "antenna.radiowaves.left.and.right"
        }
    }
}

/// IOBluetoothConnectionObserver is the nonisolated Objective-C callback edge.
///
/// IOBluetooth invokes selectors on its private coordinator queue, including
/// reentrantly while global registration is still running. This proxy owns the
/// non-Sendable framework tokens behind a lock, copies device metadata on that
/// queue, and sends only immutable values to its handler. Its unchecked
/// Sendable contract is limited to the lock-protected token registry.
nonisolated private final class IOBluetoothConnectionObserver: NSObject, @unchecked Sendable {

    typealias CallbackHandler = @Sendable (IOBluetoothConnectionCallback) -> Void

    private let lock                  = NSLock()
    private let sessionID             : UInt64
    private let registerForConnections: IOBluetoothConnectionRegistrar
    private let callbackHandler       : CallbackHandler

    private var connectionNotification        : IOBluetoothUserNotification?
    private var disconnectionNotificationsByID: [String: IOBluetoothUserNotification] = [:]
    private var isActive                        = false
    private var baselineEpoch                   = UInt64.zero
    /// Non-nil while an off-main baseline is rebuilt. Transitions that race it
    /// wait here, so the main actor still applies the baseline first.
    private var deferredCallbacks               : [IOBluetoothConnectionCallback]?

    init(
        sessionID            : UInt64,
        registerForConnections: @escaping IOBluetoothConnectionRegistrar,
        callbackHandler      : @escaping CallbackHandler
    ) {
        self.sessionID              = sessionID
        self.registerForConnections = registerForConnections
        self.callbackHandler        = callbackHandler
    }

    /// start activates callbacks before registering because IOBluetooth can
    /// synchronously invoke the selector from inside the registration call.
    func start() -> Bool {

        lock.withLock {
            isActive = true
        }

        guard let notification = registerForConnections(
            self,
            #selector(deviceConnected(_:device:))
        ) else {
            lock.withLock {
                isActive = false
            }
            return false
        }

        let keepsNotification = lock.withLock {
            guard isActive else {
                return false
            }

            connectionNotification = notification
            return true
        }

        guard keepsNotification else {
            notification.unregister()
            return false
        }

        return true
    }

    /// stop atomically makes queued callbacks stale before unregistering their
    /// framework tokens outside the lock.
    func stop() {

        let notifications = lock.withLock {
            isActive = false

            let notifications = (
                connectionNotification,
                Array(disconnectionNotificationsByID.values)
            )

            connectionNotification = nil
            disconnectionNotificationsByID.removeAll(keepingCapacity: false)
            deferredCallbacks = nil
            return notifications
        }

        notifications.0?.unregister()

        for notification in notifications.1 {
            notification.unregister()
        }
    }

    /// beginBaselineReplacement invalidates callback work already queued for
    /// the preceding startup or wake baseline.
    func beginBaselineReplacement() -> UInt64 {
        lock.withLock {
            baselineEpoch &+= 1
            deferredCallbacks = []
            return baselineEpoch
        }
    }

    /// finishBaselineReplacement resumes live delivery and returns, in arrival
    /// order, the transitions that raced the baseline rebuild.
    func finishBaselineReplacement() -> [IOBluetoothConnectionCallback] {
        lock.withLock {
            defer { deferredCallbacks = nil }
            return deferredCallbacks ?? []
        }
    }

    // ponytail: bounded at 64 transitions per rebuild; a rebuild takes a few
    // bluetoothd round trips, so a real burst that large is not expected.
    private func deliver(_ callback: IOBluetoothConnectionCallback) {
        let isDeferred = lock.withLock {
            guard deferredCallbacks != nil else { return false }
            if deferredCallbacks!.count < 64 { deferredCallbacks!.append(callback) }
            return true
        }
        if !isDeferred { callbackHandler(callback) }
    }

    /// replaceObservedDevices rebuilds per-device disconnect registrations for
    /// a silent startup or wake baseline. Old-token callbacks fail identity
    /// validation even if the framework delivers one after unregistering it.
    func replaceObservedDevices(
        _ devices: [IOBluetoothDevice]
    ) {

        let oldNotifications = lock.withLock {
            let notifications = Array(disconnectionNotificationsByID.values)
            disconnectionNotificationsByID.removeAll(keepingCapacity: true)
            return notifications
        }

        for notification in oldNotifications {
            notification.unregister()
        }

        for device in devices {
            registerDisconnectionNotification(for: device)
        }
    }

    /// deviceConnected runs on IOBluetooth's coordinator queue. It reads no
    /// main-actor state and never moves the framework device to another queue.
    @objc
    private func deviceConnected(
        _ notification: IOBluetoothUserNotification?,
        device        : IOBluetoothDevice?
    ) {

        guard let notification, let device else { return }
        let callbackEpoch: UInt64? = lock.withLock {
            guard isActive else {
                return nil
            }

            // During start the framework can call us before it returns the
            // token to store. Once stored, identity rejects old registrations.
            guard let connectionNotification else {
                return baselineEpoch
            }

            guard connectionNotification === notification else {
                return nil
            }

            return baselineEpoch
        }

        guard let callbackEpoch else {
            return
        }

        guard let deviceSnapshot = IOBluetoothDeviceSnapshot.make(from: device) else { return }
        registerDisconnectionNotification(for: device)
        deliver(
            .connected(
                identity: BluetoothConnectionCallbackIdentity(
                    sessionID    : sessionID,
                    baselineEpoch: callbackEpoch
                ),
                device: deviceSnapshot
            )
        )
    }

    /// deviceDisconnected validates the per-device token before publishing so
    /// wake replacement cannot let an old callback mutate the new baseline.
    @objc
    private func deviceDisconnected(
        _ notification: IOBluetoothUserNotification?,
        device        : IOBluetoothDevice?
    ) {

        guard let notification else { return }
        let acceptedCallback: (IOBluetoothUserNotification, String, UInt64)? = lock.withLock {
            // The framework may already have discarded addressString (or even
            // the device argument). The retained per-device token still owns
            // the correct address and also rejects a stale wake registration.
            guard isActive,
                  let registration = disconnectionNotificationsByID.first(where: {
                    $0.value === notification
                  }) else { return nil }

            disconnectionNotificationsByID[registration.key] = nil
            return (registration.value, registration.key, baselineEpoch)
        }

        guard let acceptedCallback else { return }
        acceptedCallback.0.unregister()
        deliver(
            .disconnected(
                identity: BluetoothConnectionCallbackIdentity(
                    sessionID    : sessionID,
                    baselineEpoch: acceptedCallback.2
                ),
                deviceID: acceptedCallback.1
            )
        )
    }

    /// registerDisconnectionNotification installs at most one retained token
    /// per address. A racing duplicate is unregistered immediately.
    private func registerDisconnectionNotification(
        for device: IOBluetoothDevice
    ) {

        guard let deviceID = IOBluetoothDeviceSnapshot.stableIdentifier(for: device) else { return }
        let canRegister = lock.withLock {
            isActive && disconnectionNotificationsByID[deviceID] == nil
        }

        guard canRegister,
              let notification = device.register(
                forDisconnectNotification: self,
                selector                 : #selector(deviceDisconnected(_:device:))
              ) else {
            return
        }

        let keepsNotification = lock.withLock {
            guard isActive, disconnectionNotificationsByID[deviceID] == nil else {
                return false
            }

            disconnectionNotificationsByID[deviceID] = notification
            return true
        }

        if !keepsNotification {
            notification.unregister()
        }
    }

    deinit {
        stop()
    }
}

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
    private let audioRouteMonitor = BluetoothAudioRouteMonitor()
    private var audioRouteTask: Task<Void, Never>?
    private var baselineTask  : Task<Void, Never>?
    private static let baselineQueue = DispatchQueue(label: "hylo.Cascade.bluetooth-baseline", qos: .utility)
    private let logger = Logger(subsystem: "hylo.Cascade", category: "BluetoothMonitor")

    private let metadataEnricher = BluetoothMetadataEnricher()
    private var nextEventID = UInt64.zero
    private var reducer   = BluetoothConnectionReducer()
    private var callbackGate = BluetoothConnectionCallbackGate()
    private var sessionID = UInt64.zero
    private var isRunning = false

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
        let streamPair = AsyncStream<BluetoothConnectionEvent>.makeStream(
            bufferingPolicy: .bufferingNewest(Self.streamBufferLimit)
        )

        continuation = streamPair.continuation
        streamPair.continuation.onTermination = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.sessionID == currentSessionID else {
                    return
                }

                self.stop()
            }
        }

        let notificationObserver = IOBluetoothConnectionObserver(
            sessionID            : currentSessionID,
            registerForConnections: registerForConnections,
            callbackHandler      : { [weak self] callback in
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

        guard isRunning else {
            return
        }

        switch callback {
        case .connected(let identity, let device):
            guard callbackGate.accepts(identity),
                  let event = reducer.recordConnection(
                    device,
                    eventID: nextEventID &+ 1
                  ) else {
                return
            }
            nextEventID &+= 1
            publishConnection(event, identity: identity)

        case .disconnected(let identity, let deviceID):
            guard callbackGate.accepts(identity),
                  let event = reducer.recordDisconnection(
                    deviceID: deviceID,
                    eventID : nextEventID &+ 1
                  ) else {
                return
            }
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
        _ event: BluetoothConnectionEvent,
        identity: BluetoothConnectionCallbackIdentity
    ) {
        logger.info("Bluetooth notice event: \(event.kind == .audioRoute ? "audio-route" : "connection", privacy: .public)")
        continuation?.yield(event)
        metadataEnricher.enrich(deviceID: event.deviceID) { [weak self] metadata in
            guard let self, self.isRunning, self.callbackGate.accepts(identity),
                  let update = self.reducer.enrichConnection(
                    deviceID: event.deviceID,
                    eventID: event.eventID,
                    metadata: metadata
                  ) else { return }
            self.continuation?.yield(update)
        }
    }

    /// workspaceDidWake reconciles the current connections as a new silent
    /// baseline because IOBluetooth callbacks may be stale or absent over sleep.
    private func workspaceDidWake(sessionID callbackSessionID: UInt64) {

        guard isRunning, callbackSessionID == sessionID else {
            return
        }

        rebuildBaseline()
    }

    /// rebuildBaseline enumerates cached paired and recent devices only, on a
    /// utility queue: each call is a synchronous bluetoothd round trip and the
    /// first one initializes IOBluetooth, which would stall launch and wake on
    /// the main thread. Transitions that race it are held by the observer and
    /// replayed after the baseline, preserving the synchronous ordering.
    private func rebuildBaseline() {

        guard let notificationObserver else {
            return
        }

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
                    continuation.resume(returning: connectedDevices.compactMap(IOBluetoothDeviceSnapshot.make(from:)))
                }
            }
            guard !Task.isCancelled, let self, self.isRunning,
                  self.callbackGate.accepts(identity) else { return }
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
        let identity = callbackGate.identity
        let routeStream = audioRouteMonitor.start()
        audioRouteTask = Task { [weak self] in
            for await device in routeStream {
                guard !Task.isCancelled, let self, self.isRunning,
                      self.callbackGate.accepts(identity) else { return }
                self.receiveAudioRoute(device, identity: identity)
            }
        }
    }

}
