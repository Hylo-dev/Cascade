//
//  SpotlightAccessibilityMonitor.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices

/// SpotlightAccessibilityMonitor owns all AX state on one serial worker queue.
/// Its app-lifetime owner retains it while the observer is installed; callbacks
/// only enqueue work. Stop removes the run-loop source before releasing AX state.
/// Event-driven observation is idle between changes; retries exist only during
/// the bounded native-opening handoff, never as a background poll.
nonisolated final class SpotlightAccessibilityMonitor: SpotlightAccessibilityMonitoring, @unchecked Sendable {

    private let queue    = DispatchQueue(label: "hylo.Cascade.SpotlightAX", qos: .userInitiated)
    private let onChange: @Sendable (SpotlightWindowSnapshot) -> Void
    private let gate     = SpotlightAXOperationGate()

    private var revision        : UInt64 = 0
    private var operation       : SpotlightAXOperationGate.Operation?
    private var inspectionFailed = false

    private var app           : AXUIElement?
    private var observer      : AXObserver?
    private var observedWindow: AXUIElement?
    private var processID     : pid_t = 0

    private var landingFrame    : CGRect?
    private var desktopTop      : CGFloat = 0
    private var screenSize       = CGSize.zero
    private var generation      : UInt64 = 0
    private var originalPosition: CGPoint?

    private var retry: DispatchWorkItem?

    init(onChange: @escaping @Sendable (SpotlightWindowSnapshot) -> Void) {
        self.onChange = onChange
    }

    func start(
        processID : pid_t,
        generation: UInt64
    ) {
        let revision = gate.advance()

        queue.async { [self] in
            guard gate.isCurrent(revision) else { return }

            self.revision = revision
            stopOnQueue()

            self.generation = generation
            self.processID  = processID

            let app = AXUIElementCreateApplication(processID)
            AXUIElementSetMessagingTimeout(app, 0.04)
            self.app = app

            var observer: AXObserver?
            guard AXObserverCreate(
                processID,
                { _, _, _, context in
                    guard let context else { return }

                    let owner = Unmanaged<SpotlightAccessibilityMonitor>.fromOpaque(context).takeUnretainedValue()
                    owner.queue.async { owner.inspect() }
                },
                &observer
            ) == .success,
            let observer
            else { return }

            self.observer = observer
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)

            for name in [
                kAXWindowCreatedNotification,
                kAXFocusedWindowChangedNotification,
                kAXApplicationHiddenNotification,
                kAXApplicationShownNotification
            ] {
                // Restoration may have used its whole budget. Give each of
                // these four setup requests a fresh, individually bounded turn.
                operation = gate.operation(revision: revision)
                _ = subscribe(app, name)
            }

            inspect()
        }
    }

    func prepare(
        landingFrame: CGRect,
        desktopTop  : CGFloat,
        screenSize  : CGSize,
        generation  : UInt64
    ) {
        let revision = gate.advance()

        queue.async { [self] in
            guard gate.isCurrent(revision) else { return }

            self.revision     = revision
            self.landingFrame = landingFrame
            self.desktopTop   = desktopTop
            self.screenSize   = screenSize
            self.generation   = generation

            if !inspect() { scheduleRetry(remaining: 10, generation: generation) }
        }
    }

    func clearTarget(generation: UInt64) {
        let revision = gate.advance()

        queue.async { [self] in
            guard gate.isCurrent(revision) else { return }

            self.revision   = revision
            self.generation = generation

            retry?.cancel()
            retry        = nil
            landingFrame = nil

            inspect()
        }
    }

    func stop() {
        let revision = gate.advance()

        queue.async { [self] in
            guard gate.isCurrent(revision) else { return }

            self.revision = revision
            stopOnQueue()
        }
    }

    private func stopOnQueue() {
        operation = gate.operation(revision: revision)
        retry?.cancel()
        retry = nil

        if let observer {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes)
        }

        // Campo invalidates AX proxies across close/reopen even when the window
        // number is reused. Restoration must use a freshly enumerated window.
        if let originalPosition, let app, let window = searchWindow(in: app)?.window {
            _ = move(window, to: originalPosition)
        }

        observer         = nil
        observedWindow   = nil
        originalPosition = nil
        landingFrame     = nil
        app              = nil
    }

    private func subscribe(
        _ element: AXUIElement,
        _ name   : String
    ) -> Bool {
        guard let observer, configureTimeout(element) else { return false }

        let result = AXObserverAddNotification(
            observer,
            element,
            name as CFString,
            Unmanaged.passUnretained(self).toOpaque()
        )

        // Unsupported notifications are permanent capabilities of that element;
        // interrupted/timed-out requests remain retryable on the next inspection.
        return result == .success || result == .notificationAlreadyRegistered || result == .notificationUnsupported
    }

    private func scheduleRetry(
        remaining : Int,
        generation: UInt64
    ) {
        guard gate.isCurrent(revision),
              remaining > 0,
              self.generation == generation,
              landingFrame != nil
        else { return }

        let item = DispatchWorkItem { [weak self] in
            guard let self,
                  self.gate.isCurrent(self.revision),
                  self.generation == generation,
                  self.landingFrame != nil
            else { return }

            if !self.inspect() { self.scheduleRetry(remaining: remaining - 1, generation: generation) }
        }

        retry?.cancel()
        retry = item
        queue.asyncAfter(deadline: .now() + 0.07, execute: item)
    }

    /// inspect refuses the display-sized surface Campo uses during animation.
    /// Results may grow downward, so only the top and center are constrained.
    @discardableResult
    private func inspect() -> Bool {
        inspectionFailed = false
        operation        = gate.operation(revision: revision)

        guard gate.isCurrent(revision), let app else { return false }

        guard let match = searchWindow(in: app) else {
            guard hasBudget, !inspectionFailed else { return false }

            observedWindow = nil
            onChange(SpotlightWindowSnapshot(
                generation: generation,
                processID : processID,
                isVisible : false,
                isFocused : false,
                isSettled : false,
                isReady   : false,
                frame     : nil
            ))
            return false
        }

        guard var point = position(of: match.window),
              let size = size(of: match.window)
        else { return false }

        if observedWindow == nil || position(of: observedWindow!) == nil || !CFEqual(observedWindow!, match.window) {
            var subscribed = true
            for name in [kAXMovedNotification, kAXResizedNotification, kAXUIElementDestroyedNotification] {
                if !subscribe(match.window, name) { subscribed = false }
            }
            if !subscribe(match.field, kAXFocusedUIElementChangedNotification) { subscribed = false }

            observedWindow = subscribed ? match.window : nil
        }

        let settled = size.width >= 200 && size.width < screenSize.width * 0.9
            && size.height >= 40 && size.height < screenSize.height * 0.9
        var positioned = false
        if let landingFrame, settled {
            if originalPosition == nil { originalPosition = point }

            let target = CGPoint(
                x: landingFrame.midX - size.width / 2,
                y: desktopTop - landingFrame.maxY
            )
            if abs(point.x - target.x) > 0.5 || abs(point.y - target.y) > 0.5 {
                _ = move(match.window, to: target)
                point = position(of: match.window) ?? point
            }

            positioned = abs(point.x - target.x) < 1 && abs(point.y - target.y) < 1
        }

        let focused = attribute(match.field, kAXFocusedAttribute) as? Bool
        guard hasBudget, !inspectionFailed else { return false }

        let ready = positioned && focused == true
        if ready {
            retry?.cancel()
            retry = nil
        }

        onChange(SpotlightWindowSnapshot(
            generation: generation,
            processID : processID,
            isVisible : true,
            isFocused : focused,
            isSettled : settled,
            isReady   : ready,
            frame     : CGRect(origin: point, size: size)
        ))
        return ready
    }

    private func searchWindow(in app: AXUIElement) -> (window: AXUIElement, field: AXUIElement)? {
        guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else {
            inspectionFailed = true
            return nil
        }

        for window in windows.prefix(12) {
            var remaining = 100
            if let field = searchField(
                in       : window,
                depth    : 0,
                remaining: &remaining
            ) {
                return (window, field)
            }
        }

        return nil
    }

    private func searchField(
        in element: AXUIElement,
        depth     : Int,
        remaining : inout Int
    ) -> AXUIElement? {
        guard hasBudget, depth < 8, remaining > 0 else { return nil }

        remaining -= 1
        if attribute(element, kAXIdentifierAttribute) as? String == "SpotlightSearchField" { return element }

        for child in (attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(24) {
            if let field = searchField(
                in       : child,
                depth    : depth + 1,
                remaining: &remaining
            ) {
                return field
            }
        }

        return nil
    }

    private var hasBudget: Bool {
        guard let operation else { return false }

        return gate.remaining(operation) > 0
    }

    /// configureTimeout sets the AX timeout on each proxy, including freshly
    /// returned children. The final budget check also prevents a cancelled
    /// inspection from moving a window when a delayed read eventually returns.
    private func configureTimeout(_ element: AXUIElement) -> Bool {
        guard let operation else { return false }

        let remaining = gate.remaining(operation)
        guard remaining > 0 else { return false }

        AXUIElementSetMessagingTimeout(element, Float(min(0.04, remaining)))
        return gate.remaining(operation) > 0
    }

    private func attribute(
        _ element: AXUIElement,
        _ name   : String
    ) -> CFTypeRef? {
        guard configureTimeout(element) else { return nil }

        var result: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, name as CFString, &result)
        if error != .success && error != .attributeUnsupported && error != .noValue {
            inspectionFailed = true
        }

        return error == .success ? result : nil
    }

    private func position(of element: AXUIElement) -> CGPoint? {
        guard let value = attribute(element, kAXPositionAttribute),
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    private func size(of element: AXUIElement) -> CGSize? {
        guard let value = attribute(element, kAXSizeAttribute),
              CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }

        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    private func move(
        _ element: AXUIElement,
        to point : CGPoint
    ) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point),
              configureTimeout(element)
        else { return .failure }

        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value)
    }
}
