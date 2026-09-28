//
//  FocusedWindowMonitor.swift
//  CascadeKit
//

import AppKit
@preconcurrency import ApplicationServices

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
