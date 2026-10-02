//
//  IOBluetoothConnectionObserver.swift
//  CascadeKit
//

import Foundation
import IOBluetooth

typealias IOBluetoothConnectionRegistrar = @Sendable (AnyObject, Selector) -> IOBluetoothUserNotification?

/// IOBluetoothConnectionObserver is the nonisolated Objective-C callback edge.
///
/// IOBluetooth invokes selectors on its private coordinator queue, including
/// reentrantly while global registration is still running. This proxy owns the
/// non-Sendable framework tokens behind a lock, copies device metadata on that
/// queue, and sends only immutable values to its handler. Its unchecked
/// Sendable contract is limited to the lock-protected token registry.
///
/// The Bluetooth source starts and stops it on the main queue: IOBluetooth
/// delivers through the run loop of the thread that registered, and PluginHost's
/// main thread runs one.
final class IOBluetoothConnectionObserver: NSObject, BluetoothConnectionObserving, @unchecked Sendable {

    typealias CallbackHandler = @Sendable (IOBluetoothConnectionCallback) -> Void

    private let lock                   = NSLock()
    private let sessionID             : UInt64
    private let registerForConnections: IOBluetoothConnectionRegistrar
    private let callbackHandler       : CallbackHandler

    private var connectionNotification        : IOBluetoothUserNotification?
    private var disconnectionNotificationsByID: [String: IOBluetoothUserNotification] = [:]
    private var isActive                       = false
    private var baselineEpoch                  = UInt64.zero
    /// Non-nil while a baseline is rebuilt. Transitions that race it wait
    /// here, so the source still applies the baseline first.
    private var deferredCallbacks             : [IOBluetoothConnectionCallback]?

    init(
        sessionID             : UInt64,
        registerForConnections: @escaping IOBluetoothConnectionRegistrar,
        callbackHandler       : @escaping CallbackHandler
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
            guard isActive else { return false }

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

    /// connectedDevices reads the devices connected now for a silent startup or
    /// wake baseline and watches each one's disconnection. Every call is a few
    /// synchronous bluetoothd round trips, so it runs on the source's queue.
    func connectedDevices() -> [BluetoothConnectedDevice] {
        let devices = IOBluetoothDeviceSnapshot.connectedDevices()
        replaceObservedDevices(devices)

        return devices.compactMap(IOBluetoothDeviceSnapshot.make(from:))
    }

    /// replaceObservedDevices rebuilds per-device disconnect registrations for
    /// a silent startup or wake baseline. Old-token callbacks fail identity
    /// validation even if the framework delivers one after unregistering it.
    private func replaceObservedDevices(_ devices: [IOBluetoothDevice]) {
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

    /// deviceConnected runs wherever IOBluetooth delivers it. It reads no
    /// source state and never moves the framework device to another queue.
    @objc
    private func deviceConnected(
        _ notification: IOBluetoothUserNotification?,
        device        : IOBluetoothDevice?
    ) {
        guard let notification, let device else { return }

        let callbackEpoch: UInt64? = lock.withLock {
            guard isActive else { return nil }

            // During start the framework can call us before it returns the
            // token to store. Once stored, identity rejects old registrations.
            guard let connectionNotification else { return baselineEpoch }
            guard connectionNotification === notification else { return nil }

            return baselineEpoch
        }

        guard let callbackEpoch else { return }
        guard let deviceSnapshot = IOBluetoothDeviceSnapshot.make(from: device) else { return }

        registerDisconnectionNotification(for: device)
        deliver(
            .connected(
                identity: BluetoothConnectionCallbackIdentity(
                    sessionID    : sessionID,
                    baselineEpoch: callbackEpoch
                ),
                device  : deviceSnapshot
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
                  })
            else { return nil }

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
    private func registerDisconnectionNotification(for device: IOBluetoothDevice) {
        guard let deviceID = IOBluetoothDeviceSnapshot.stableIdentifier(for: device) else { return }

        let canRegister = lock.withLock {
            isActive && disconnectionNotificationsByID[deviceID] == nil
        }

        guard canRegister,
              let notification = device.register(
                  forDisconnectNotification: self,
                  selector                 : #selector(deviceDisconnected(_:device:))
              )
        else { return }

        let keepsNotification = lock.withLock {
            guard isActive, disconnectionNotificationsByID[deviceID] == nil else { return false }

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
