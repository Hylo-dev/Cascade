//
//  AccessibilityFocusedWindowTransport.swift
//  CascadeKit
//

import AppKit
@preconcurrency import ApplicationServices

/// AccessibilityFocusedWindowTransport owns the AX observer and all remote
/// reads. Its methods are called only by FocusedWindowMonitor's serial worker.
nonisolated final class AccessibilityFocusedWindowTransport: FocusedWindowTransport, @unchecked Sendable {
    private let messageTimeout: Float
    private var changeHandler : (@Sendable () -> Void)?
    private var processID     : pid_t?
    private var application   : AXUIElement?
    private var observer      : AXObserver?
    private var observedWindow: AXUIElement?
    private var callbackContext: FocusedWindowAXCallbackContext?
    private var callbackPointer: UnsafeMutableRawPointer?

    init(messageTimeout: Float = 0.04) {
        self.messageTimeout = messageTimeout
    }

    func start(onChange: @escaping @Sendable () -> Void) {
        changeHandler = onChange
    }

    func requestSnapshot(
        processID: pid_t?,
        completion: @escaping @Sendable (FocusedWindowTransportResult) -> Void
    ) {
        guard AXIsProcessTrusted() else {
            tearDownObservation()
            completion(.permissionDenied)
            return
        }

        guard let processID else {
            tearDownObservation()
            completion(.unavailable)
            return
        }

        if self.processID != processID {
            installApplicationObservation(processID: processID)
        }

        guard let application,
              let windowValue = attribute(application, kAXFocusedWindowAttribute),
              CFGetTypeID(windowValue) == AXUIElementGetTypeID() else {
            clearWindowObservation()
            completion(.unavailable)
            return
        }
        // CoreFoundation erases the concrete reference type to `AnyObject`.
        // The runtime type-ID guard above is the checked boundary for this cast.
        let window = unsafeBitCast(windowValue, to: AXUIElement.self)

        observeWindowIfNeeded(window)

        if attribute(window, kAXMinimizedAttribute) as? Bool == true {
            completion(.unavailable)
            return
        }

        guard let position = pointAttribute(window, kAXPositionAttribute),
              let size = sizeAttribute(window, kAXSizeAttribute),
              size.width > 0,
              size.height > 0 else {
            completion(.unavailable)
            return
        }

        completion(.frameInAXCoordinates(CGRect(
            origin: position,
            size  : size
        )))
    }

    func stop() {
        changeHandler = nil
        tearDownObservation()
    }

    private func installApplicationObservation(processID: pid_t) {
        tearDownObservation()

        let application = AXUIElementCreateApplication(processID)
        configureTimeout(application)

        var observer: AXObserver?
        guard AXObserverCreate(
            processID,
            { _, _, _, contextPointer in
                guard let contextPointer else {
                    return
                }
                let context = Unmanaged<FocusedWindowAXCallbackContext>
                    .fromOpaque(contextPointer)
                    .takeUnretainedValue()
                context.signal()
            },
            &observer
        ) == .success, let observer else {
            return
        }

        let context = FocusedWindowAXCallbackContext(handler: changeHandler)
        let contextPointer = Unmanaged.passRetained(context).toOpaque()

        self.processID       = processID
        self.application     = application
        self.observer        = observer
        self.callbackContext = context
        self.callbackPointer = contextPointer

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            .commonModes
        )

        for notification in Self.applicationNotifications {
            addNotification(
                notification,
                element       : application,
                observer      : observer,
                contextPointer: contextPointer
            )
        }
    }

    private func observeWindowIfNeeded(_ window: AXUIElement) {
        if let observedWindow, CFEqual(observedWindow, window) {
            return
        }

        clearWindowObservation()
        guard let observer, let callbackPointer else {
            return
        }

        for notification in Self.windowNotifications {
            addNotification(
                notification,
                element       : window,
                observer      : observer,
                contextPointer: callbackPointer
            )
        }
        observedWindow = window
    }

    private func clearWindowObservation() {
        guard let observer, let observedWindow else {
            self.observedWindow = nil
            return
        }

        for notification in Self.windowNotifications {
            AXObserverRemoveNotification(
                observer,
                observedWindow,
                notification as CFString
            )
        }
        self.observedWindow = nil
    }

    private func tearDownObservation() {
        clearWindowObservation()

        if let observer, let application {
            for notification in Self.applicationNotifications {
                AXObserverRemoveNotification(
                    observer,
                    application,
                    notification as CFString
                )
            }
        }

        callbackContext?.cancel()
        if let observer, let callbackPointer {
            let source = AXObserverGetRunLoopSource(observer)
            let runLoop = CFRunLoopGetMain()
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.commonModes.rawValue) {
                CFRunLoopRemoveSource(runLoop, source, .commonModes)
                Unmanaged<FocusedWindowAXCallbackContext>
                    .fromOpaque(callbackPointer)
                    .release()
            }
            CFRunLoopWakeUp(runLoop)
        }

        processID        = nil
        application      = nil
        observer         = nil
        observedWindow   = nil
        callbackContext  = nil
        callbackPointer  = nil
    }

    private func addNotification(
        _ notification: String,
        element       : AXUIElement,
        observer      : AXObserver,
        contextPointer: UnsafeMutableRawPointer
    ) {
        configureTimeout(element)
        _ = AXObserverAddNotification(
            observer,
            element,
            notification as CFString,
            contextPointer
        )
    }

    private func attribute(
        _ element: AXUIElement,
        _ name   : String
    ) -> CFTypeRef? {
        configureTimeout(element)
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
            ? value
            : nil
    }

    private func pointAttribute(
        _ element: AXUIElement,
        _ name   : String
    ) -> CGPoint? {
        guard let value = attribute(element, name),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        // CoreFoundation erases AXValue behind CFTypeRef; the type-ID check is
        // the runtime proof required before recovering the concrete reference.
        let axValue = unsafeBitCast(value, to: AXValue.self)

        var point = CGPoint.zero
        return AXValueGetValue(
            axValue,
            .cgPoint,
            &point
        ) ? point : nil
    }

    private func sizeAttribute(
        _ element: AXUIElement,
        _ name   : String
    ) -> CGSize? {
        guard let value = attribute(element, name),
              CFGetTypeID(value) == AXValueGetTypeID() else {
            return nil
        }
        // CoreFoundation erases AXValue behind CFTypeRef; the type-ID check is
        // the runtime proof required before recovering the concrete reference.
        let axValue = unsafeBitCast(value, to: AXValue.self)

        var size = CGSize.zero
        return AXValueGetValue(
            axValue,
            .cgSize,
            &size
        ) ? size : nil
    }

    private func configureTimeout(_ element: AXUIElement) {
        AXUIElementSetMessagingTimeout(element, messageTimeout)
    }

    private static let applicationNotifications = [
        kAXFocusedWindowChangedNotification,
        kAXWindowCreatedNotification,
        kAXApplicationHiddenNotification,
        kAXApplicationShownNotification,
    ]

    private static let windowNotifications = [
        kAXMovedNotification,
        kAXResizedNotification,
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXUIElementDestroyedNotification,
    ]
}

/// FocusedWindowAXCallbackContext keeps AX's raw context alive until its main
/// run-loop source is removed. Cancelling first makes already queued callbacks
/// harmless during app replacement, stop and owner deallocation.
nonisolated final class FocusedWindowAXCallbackContext: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: (@Sendable () -> Void)?

    init(handler: (@Sendable () -> Void)?) {
        self.handler = handler
    }

    func signal() {
        let handler = lock.withLock { self.handler }
        handler?()
    }

    func cancel() {
        lock.withLock { handler = nil }
    }
}
