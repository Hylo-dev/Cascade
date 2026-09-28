//
//  FocusedWindowMonitor.swift
//  CascadeKit
//

import AppKit
@preconcurrency import ApplicationServices

/// FocusedWindowMonitoring publishes the external focused window in global
/// AppKit coordinates. A nil frame means focus is unavailable and callers must
/// use their pointer/main-display fallback.
@MainActor
protocol FocusedWindowMonitoring: AnyObject {
    var onChange: ((CGRect?) -> Void)? { get set }

    func start()
    func stop()
    func refresh()
}

/// FocusedApplication is the small, Sendable identity needed for an AX lookup.
nonisolated struct FocusedApplication: Equatable, Sendable {
    let processID      : pid_t
    let bundleIdentifier: String?
}

/// FocusedApplicationMonitoring owns public workspace activation observation.
/// It also reports System Settings deactivation so returning from the privacy
/// pane rechecks trust without a private permission notification or polling.
@MainActor
protocol FocusedApplicationMonitoring: AnyObject {
    var onChange: (() -> Void)? { get set }
    var frontmostApplication: FocusedApplication? { get }

    func start()
    func stop()
}

/// FocusedWindowTransportResult keeps raw AX coordinates at the worker seam so
/// coordinate normalization remains explicit and independently testable.
nonisolated enum FocusedWindowTransportResult: Equatable, Sendable {
    case frameInAXCoordinates(CGRect)
    case unavailable
    case permissionDenied
}

/// FocusedWindowTransport isolates every cross-process AX operation behind one
/// injectable worker-only boundary.
nonisolated protocol FocusedWindowTransport: AnyObject, Sendable {
    func start(onChange: @escaping @Sendable () -> Void)
    func requestSnapshot(
        processID: pid_t?,
        completion: @escaping @Sendable (FocusedWindowTransportResult) -> Void
    )
    func stop()
}

/// FocusedWindowCoordinateSpace converts Accessibility's top-left, downward-y
/// desktop space into AppKit's global bottom-left, upward-y space.
nonisolated enum FocusedWindowCoordinateSpace {

    /// appKitFrame preserves x because both spaces share the primary display's
    /// horizontal origin and reflects y around that display's AppKit top edge.
    static func appKitFrame(
        fromAXFrame frame: CGRect,
        desktopTop         : CGFloat
    ) -> CGRect? {
        guard desktopTop.isFinite,
              !frame.isNull,
              !frame.isInfinite,
              frame.origin.x.isFinite,
              frame.origin.y.isFinite,
              frame.width.isFinite,
              frame.height.isFinite,
              frame.width > 0,
              frame.height > 0 else {
            return nil
        }

        return CGRect(
            x     : frame.minX,
            y     : desktopTop - frame.maxY,
            width : frame.width,
            height: frame.height
        )
    }
}

/// FocusedWindowMonitor coalesces event bursts and publishes only current AX
/// generations. Reads and observer replacement run on one serial worker; the
/// main actor only captures app/display metadata and delivers immutable frames.
@MainActor
final class FocusedWindowMonitor: FocusedWindowMonitoring {
    var onChange: ((CGRect?) -> Void)?

    private let applicationMonitor: any FocusedApplicationMonitoring
    private let transport         : any FocusedWindowTransport
    private let desktopTop        : @MainActor () -> CGFloat
    private let worker            : DispatchQueue
    private let coalescingDelay   : TimeInterval
    private var pendingRequest    : FocusedWindowRequestToken?
    private var generation        : UInt64 = 0
    private var isStarted         = false
    private var hasPublished      = false
    private var publishedFrame    : CGRect?

    convenience init() {
        self.init(
            applicationMonitor: WorkspaceFocusedApplicationMonitor(),
            transport         : AccessibilityFocusedWindowTransport()
        )
    }

    init(
        applicationMonitor: any FocusedApplicationMonitoring,
        transport         : any FocusedWindowTransport,
        desktopTop        : @escaping @MainActor () -> CGFloat = {
            let mainDisplayID = CGMainDisplayID()
            return NSScreen.screens.first { $0.displayID == mainDisplayID }?.frame.maxY
                ?? NSScreen.screens.first?.frame.maxY
                ?? 0
        },
        worker            : DispatchQueue = DispatchQueue(
            label: "hylo.Cascade.FocusedWindowAX",
            qos  : .userInitiated
        ),
        coalescingDelay: TimeInterval = 0.012
    ) {
        self.applicationMonitor = applicationMonitor
        self.transport          = transport
        self.desktopTop         = desktopTop
        self.worker             = worker
        self.coalescingDelay    = coalescingDelay
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted      = true
        hasPublished   = false
        publishedFrame = nil
        applicationMonitor.onChange = { [weak self] in
            self?.scheduleRefresh()
        }
        applicationMonitor.start()

        let transport = transport
        let observedChange: @Sendable () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                self?.scheduleRefresh()
            }
        }
        worker.async {
            transport.start(onChange: observedChange)
        }
        scheduleRefresh()
    }

    func stop() {
        guard isStarted else {
            return
        }

        isStarted = false
        generation &+= 1
        pendingRequest?.cancel()
        pendingRequest = nil
        applicationMonitor.onChange = nil
        applicationMonitor.stop()

        let transport = transport
        worker.async {
            transport.stop()
        }
    }

    /// refresh lets the app's existing public return-from-settings path trigger
    /// a trust recheck without installing a second permission observer here.
    func refresh() {
        scheduleRefresh()
    }

    private func scheduleRefresh() {
        guard isStarted else {
            return
        }

        generation &+= 1
        let requestGeneration = generation
        let token = FocusedWindowRequestToken()
        pendingRequest?.cancel()
        pendingRequest = token

        let application = applicationMonitor.frontmostApplication
        let processID = application?.processID == ProcessInfo.processInfo.processIdentifier
            ? nil
            : application?.processID
        let desktopTop = desktopTop()
        let transport  = transport

        let deliver: @Sendable (FocusedWindowTransportResult) -> Void = { [weak self] result in
            Task { @MainActor [weak self] in
                self?.accept(
                    result    : result,
                    desktopTop: desktopTop,
                    generation: requestGeneration,
                    token     : token
                )
            }
        }

        worker.asyncAfter(deadline: .now() + coalescingDelay) {
            guard !token.isCancelled else {
                return
            }

            transport.requestSnapshot(
                processID: processID,
                completion: deliver
            )
        }
    }

    private func accept(
        result    : FocusedWindowTransportResult,
        desktopTop: CGFloat,
        generation: UInt64,
        token     : FocusedWindowRequestToken
    ) {
        guard isStarted,
              self.generation == generation,
              !token.isCancelled else {
            return
        }

        let frame: CGRect?
        switch result {
        case .frameInAXCoordinates(let rawFrame):
            frame = FocusedWindowCoordinateSpace.appKitFrame(
                fromAXFrame: rawFrame,
                desktopTop : desktopTop
            )
        case .unavailable, .permissionDenied:
            frame = nil
        }

        guard !hasPublished || frame != publishedFrame else {
            return
        }

        hasPublished   = true
        publishedFrame = frame
        onChange?(frame)
    }
}

/// FocusedWindowRequestToken cancels coalesced work before it enters the AX
/// transport while generation checks reject work already in flight.
nonisolated private final class FocusedWindowRequestToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }
}

/// WorkspaceFocusedApplicationMonitor translates public NSWorkspace events
/// into cheap invalidations. The AX worker remains responsible for real trust.
@MainActor
private final class WorkspaceFocusedApplicationMonitor: NSObject, FocusedApplicationMonitoring {
    var onChange: (() -> Void)?

    private let workspace: NSWorkspace
    private var isStarted = false

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
        super.init()
    }

    var frontmostApplication: FocusedApplication? {
        guard let application = workspace.frontmostApplication else {
            return nil
        }

        return FocusedApplication(
            processID      : application.processIdentifier,
            bundleIdentifier: application.bundleIdentifier
        )
    }

    func start() {
        guard !isStarted else {
            return
        }

        isStarted = true
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(applicationActivated),
            name    : NSWorkspace.didActivateApplicationNotification,
            object  : nil
        )
        workspace.notificationCenter.addObserver(
            self,
            selector: #selector(applicationDeactivated),
            name    : NSWorkspace.didDeactivateApplicationNotification,
            object  : nil
        )
    }

    func stop() {
        guard isStarted else {
            return
        }

        workspace.notificationCenter.removeObserver(self)
        isStarted = false
    }

    @objc
    private func applicationActivated() {
        onChange?()
    }

    @objc
    private func applicationDeactivated(_ notification: Notification) {
        let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication
        guard application?.bundleIdentifier == "com.apple.systempreferences" else {
            return
        }
        onChange?()
    }

    deinit {
        workspace.notificationCenter.removeObserver(self)
    }
}

/// AccessibilityFocusedWindowTransport owns the AX observer and all remote
/// reads. Its methods are called only by FocusedWindowMonitor's serial worker.
nonisolated private final class AccessibilityFocusedWindowTransport: FocusedWindowTransport, @unchecked Sendable {
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
nonisolated private final class FocusedWindowAXCallbackContext: @unchecked Sendable {
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
