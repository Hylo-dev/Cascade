//
//  MouseEventMonitor.swift
//  CascadeKit
//

import AppKit
import QuartzCore

/// MouseEventMonitor is the AppKit-backed event source.
///
/// It uses a *global* `NSEvent` monitor for mouse movement (which needs no
/// accessibility permission, unlike key or tap monitoring) plus a *local* one,
/// so the notch keeps tracking the pointer even while our own overlay is
/// frontmost. Pointer events are throttled to roughly the display cadence
/// before they reach the controller: the raw stream can fire far faster than we
/// need, and waking the state machine on every sub-pixel jitter is exactly the
/// kind of battery waste the project forbids.
final class MouseEventMonitor: EventMonitoring {

    var onPointerMoved               : ((CGPoint) -> Void)?
    var onPointerButtonChanged       : ((Bool) -> Void)?
    var onActiveDisplayMayHaveChanged: (() -> Void)?
    var onSpaceChanged               : (() -> Void)?
    var onScreenLocked               : (() -> Void)?
    var onScreenUnlocked             : (() -> Void)?
    var onScreensAsleepChanged       : ((Bool) -> Void)?

    private var globalMouse: Any?
    private var localMouse : Any?
    private var lastEmit   : CFTimeInterval = 0

    private var fileDragRecognitionHandler: ((Bool, CGPoint, Bool) -> Void)?
    private var fileDragRecognizer         = NativeFileDragRecognitionReducer()

    private let validatesNativeFileDragOfferHint: (NSPasteboard, Int) -> Bool

    /// Minimum spacing between forwarded pointer events (~120 Hz).
    private let throttleInterval: CFTimeInterval = 1.0 / 120.0

    init(validatesNativeFileDragOfferHint: ((NSPasteboard, Int) -> Bool)? = nil) {
        self.validatesNativeFileDragOfferHint = validatesNativeFileDragOfferHint
            ?? { pasteboard, changeCount in
                NativeFileDragOfferHint.validates(pasteboard, changeCount: changeCount)
            }
    }

    func start() {
        guard globalMouse == nil, localMouse == nil else { return }

        let mask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .leftMouseDown,
            .leftMouseUp,
            .leftMouseDragged,
            .rightMouseDown,
            .rightMouseUp,
            .rightMouseDragged,
            .otherMouseDown,
            .otherMouseUp,
            .otherMouseDragged
        ]

        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
        }

        localMouse = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }

        // App activation is only a nudge: the display coordinator answers it
        // by refreshing its focused-window monitor. This observer performs no
        // AX work and does not define focus ownership.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeDisplayMayHaveChanged),
            name    : NSWorkspace.didActivateApplicationNotification,
            object  : nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(activeDisplayMayHaveChanged),
            name    : NSApplication.didChangeScreenParametersNotification,
            object  : nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(spaceChanged),
            name    : NSWorkspace.activeSpaceDidChangeNotification,
            object  : nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensSlept),
            name    : NSWorkspace.screensDidSleepNotification,
            object  : nil
        )

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(screensWoke),
            name    : NSWorkspace.screensDidWakeNotification,
            object  : nil
        )

        // Screen lock / unlock — posted by loginwindow on the system-wide
        // distributed center. We hide the overlay while locked so it never
        // shows on the login / lock screen.
        let distributed = DistributedNotificationCenter.default()

        distributed.addObserver(
            self,
            selector: #selector(screenLocked),
            name    : NSNotification.Name("com.apple.screenIsLocked"),
            object  : nil
        )

        distributed.addObserver(
            self,
            selector: #selector(screenUnlocked),
            name    : NSNotification.Name("com.apple.screenIsUnlocked"),
            object  : nil
        )
    }

    func stop() {
        if let globalMouse {
            NSEvent.removeMonitor(globalMouse)
        }

        if let localMouse {
            NSEvent.removeMonitor(localMouse)
        }

        globalMouse = nil
        localMouse  = nil

        if let active = fileDragRecognizer.cancel() {
            fileDragRecognitionHandler?(active, NSEvent.mouseLocation, false)
        }

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    func setFileDragRecognitionHandler(_ handler: ((Bool, CGPoint, Bool) -> Void)?) {
        if handler == nil {
            _ = fileDragRecognizer.cancel()
        }

        fileDragRecognitionHandler = handler
    }

    deinit {
        stop()
    }

    /// emitPointer forwards the current pointer location, throttled to
    /// `throttleInterval`.
    private func emitPointer(force: Bool = false) {
        let now = CACurrentMediaTime()

        guard force || now - lastEmit >= throttleInterval else { return }

        lastEmit = now
        onPointerMoved?(NSEvent.mouseLocation)
    }

    /// handle keeps movement coalesced while delivering button boundaries
    /// immediately. A mouse-up must never be throttled because it releases the
    /// controller's drag hold and returns the rest of the menu bar to its owner.
    private func handle(_ event: NSEvent) {
        updateFileDragRecognition(for: event)

        switch event.type {
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                emitPointer(force: true)
                onPointerButtonChanged?(true)

            case .leftMouseUp, .rightMouseUp, .otherMouseUp:
                emitPointer(force: true)
                onPointerButtonChanged?(false)

            case .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
                emitPointer()

            default:
                break
        }
    }

    private func updateFileDragRecognition(for event: NSEvent) {
        guard fileDragRecognitionHandler != nil else { return }

        switch event.type {
            case .leftMouseDown:
                let pasteboard = NSPasteboard(name: .drag)
                if let active = fileDragRecognizer.consume(
                    .mouseDown(changeCount: pasteboard.changeCount)
                ) {
                    fileDragRecognitionHandler?(active, NSEvent.mouseLocation, false)
                }

            case .leftMouseDragged:
                let pasteboard  = NSPasteboard(name: .drag)
                let changeCount = pasteboard.changeCount
                guard fileDragRecognizer.shouldInspectDrag(changeCount: changeCount) else { return }

                if let active = fileDragRecognizer.consume(.dragged(
                    changeCount  : changeCount,
                    hasFileIntent: Self.hasFileIntent(pasteboard)
                )) {
                    let hasValidatedOfferHint = active && validatesNativeFileDragOfferHint(
                        pasteboard,
                        changeCount
                    )
                    fileDragRecognitionHandler?(
                        active,
                        NSEvent.mouseLocation,
                        hasValidatedOfferHint
                    )
                }

            case .leftMouseUp:
                if let active = fileDragRecognizer.consume(.mouseUp) {
                    fileDragRecognitionHandler?(active, NSEvent.mouseLocation, false)
                }

            case .mouseMoved where NSEvent.pressedMouseButtons & 1 == 0:
                if let active = fileDragRecognizer.cancelStaleGesture() {
                    fileDragRecognitionHandler?(active, NSEvent.mouseLocation, false)
                }

            default:
                return
        }
    }

    private static func hasFileIntent(_ pasteboard: NSPasteboard) -> Bool {
        let promiseTypes: Set<NSPasteboard.PasteboardType> = [
            .init("com.apple.pasteboard.promised-file-url"),
            .init("com.apple.pasteboard.promised-file-content-type")
        ]

        return pasteboard.pasteboardItems?.contains { item in
            item.types.contains(.fileURL) || !promiseTypes.isDisjoint(with: item.types)
        } == true
    }

    @objc
    private func activeDisplayMayHaveChanged() {
        onActiveDisplayMayHaveChanged?()
    }

    @objc
    private func spaceChanged() {
        onSpaceChanged?()
    }

    @objc
    private func screenLocked() {
        onScreenLocked?()
    }

    @objc
    private func screenUnlocked() {
        onScreenUnlocked?()
    }

    @objc
    private func screensSlept() {
        onScreensAsleepChanged?(true)
    }

    @objc
    private func screensWoke() {
        onScreensAsleepChanged?(false)
    }
}
