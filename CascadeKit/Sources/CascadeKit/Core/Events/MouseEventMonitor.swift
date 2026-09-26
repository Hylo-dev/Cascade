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

    private var globalMouse: Any?
    private var localMouse : Any?
    private var lastEmit   : CFTimeInterval = 0

    /// Minimum spacing between forwarded pointer events (~120 Hz).
    private let throttleInterval: CFTimeInterval = 1.0 / 120.0

    func start() {

        guard globalMouse == nil, localMouse == nil else {
            return
        }

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

        // The single-controller bridge still uses this nudge until task 4
        // replaces it with inventory and focused-window inputs. It performs no
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

        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        DistributedNotificationCenter.default().removeObserver(self)
    }

    deinit {
        stop()
    }

    /// Forward the current pointer location, throttled to `throttleInterval`.
    private func emitPointer(force: Bool = false) {

        let now = CACurrentMediaTime()

        guard force || now - lastEmit >= throttleInterval else {
            return
        }

        lastEmit = now
        onPointerMoved?(NSEvent.mouseLocation)
    }

    /// handle keeps movement coalesced while delivering button boundaries
    /// immediately. A mouse-up must never be throttled because it releases the
    /// controller's drag hold and returns the rest of the menu bar to its owner.
    private func handle(_ event: NSEvent) {
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
}
