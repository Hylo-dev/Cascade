//
//  BluetoothMonitorLifecycleTests.swift
//  Cascade
//

#if BLUETOOTH_MONITOR_TESTS
import AppKit
import IOBluetooth

enum BluetoothMonitorLifecycleTests {

    @MainActor
    static func run() async throws {
        try await restartingFinishesThePriorStream()
        try await stoppingFinishesTheActiveStream()
        try await unavailableRegistrationIsVisibleAndFinishesTheStream()
        try await objectiveCCallbacksAcceptBackgroundDelivery()
    }

    @MainActor
    private static func restartingFinishesThePriorStream() async throws {
        let monitor     = IOBluetoothConnectionMonitor()
        let firstStream = monitor.start()

        try expectBluetoothMonitorBehavior(
            monitor.status == .monitoring,
            "A retained global registration must expose monitoring status."
        )

        _ = monitor.start()

        try await expectFinished(
            stream : firstStream,
            message: "Starting again must finish the prior stream."
        )

        monitor.stop()
    }

    @MainActor
    private static func stoppingFinishesTheActiveStream() async throws {
        let monitor = IOBluetoothConnectionMonitor()
        let stream  = monitor.start()
        monitor.stop()

        try await expectFinished(
            stream : stream,
            message: "Stopping must finish the active stream."
        )

        try expectBluetoothMonitorBehavior(
            monitor.status == .stopped,
            "Stopping must expose the stopped status."
        )

        monitor.stop()
    }

    @MainActor
    private static func unavailableRegistrationIsVisibleAndFinishesTheStream() async throws {
        let monitor = IOBluetoothConnectionMonitor { _, _ in nil }
        let stream  = monitor.start()

        guard case .unavailable(let reason) = monitor.status else {
            throw BluetoothMonitorTestFailure.assertion(
                "A failed global registration must expose unavailable status."
            )
        }

        try expectBluetoothMonitorBehavior(
            !reason.isEmpty,
            "Unavailable status must explain the registration failure."
        )

        try await expectFinished(
            stream : stream,
            message: "A failed global registration must finish its stream."
        )
    }

    @MainActor
    private static func objectiveCCallbacksAcceptBackgroundDelivery() async throws {
        let callbackProbe = BluetoothBackgroundCallbackProbe()
        let monitor       = IOBluetoothConnectionMonitor { observer, selector in
            callbackProbe.register(
                observer: observer,
                selector: selector
            )
        }

        _ = monitor.start()
        try await callbackProbe.invokeCallbacks()
        monitor.stop()
    }

    nonisolated private static func expectFinished(
        stream : AsyncStream<BluetoothConnectionEvent>,
        message: String
    ) async throws {
        var iterator = stream.makeAsyncIterator()

        guard await iterator.next() == nil else {
            throw BluetoothMonitorTestFailure.assertion(message)
        }
    }
}

/// BluetoothBackgroundCallbackProbe invokes the real Objective-C selector on
/// a background queue, matching IOBluetooth's coordinator queue delivery.
///
/// The lock owns the Objective-C objects across the test queue boundary. The
/// probe waits for invocation to finish before the monitor can unregister or
/// release them, which is the unchecked lifetime contract.
nonisolated private final class BluetoothBackgroundCallbackProbe: @unchecked Sendable {

    private let lock = NSLock()

    private var observer    : AnyObject?
    private var notification: IOBluetoothUserNotification?
    private var selector    : Selector?

    func register(
        observer: AnyObject,
        selector: Selector
    ) -> IOBluetoothUserNotification? {
        let notification = IOBluetoothDevice.register(
            forConnectNotifications: observer,
            selector               : selector
        )

        lock.withLock {
            self.observer     = observer
            self.notification = notification
            self.selector     = selector
        }

        return notification
    }

    func invokeCallbacks() async throws {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                do {
                    try invokeCallbacksOnCurrentQueue()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func invokeCallbacksOnCurrentQueue() throws {
        let callback = lock.withLock { (observer, notification, selector) }

        guard let observer = callback.0,
              let notification = callback.1,
              let selector = callback.2,
              let device = IOBluetoothDevice(addressString: "AA-BB-CC-DD-EE-FF")
        else {
            throw BluetoothMonitorTestFailure.assertion(
                "The callback probe could not build its Objective-C fixtures."
            )
        }

        // Objective-C may deliver nil objects or a device whose cached address vanished.
        _ = observer.perform(
            selector,
            with: notification,
            with: nil
        )
        _ = observer.perform(
            selector,
            with: notification,
            with: IOBluetoothDevice()
        )
        _ = observer.perform(
            NSSelectorFromString("deviceDisconnected:device:"),
            with: notification,
            with: nil
        )
        _ = observer.perform(
            NSSelectorFromString("deviceDisconnected:device:"),
            with: notification,
            with: IOBluetoothDevice()
        )
        _ = observer.perform(
            selector,
            with: notification,
            with: device
        )

        _ = observer.perform(
            NSSelectorFromString("deviceDisconnected:device:"),
            with: IOBluetoothUserNotification(),
            with: device
        )
    }
}

#endif
