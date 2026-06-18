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
    var onActiveDisplayMayHaveChanged: (() -> Void)?

    private var globalMouse: Any?
    private var localMouse : Any?
    private var lastEmit   : CFTimeInterval = 0

    /// Minimum spacing between forwarded pointer events (~120 Hz).
    private let throttleInterval: CFTimeInterval = 1.0 / 120.0

    func start() {

        let mask: NSEvent.EventTypeMask = [.mouseMoved]

        globalMouse = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            self?.emitPointer()
        }

        localMouse = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.emitPointer()
            return event
        }

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
    }

    deinit {
        stop()
    }

    /// Forward the current pointer location, throttled to `throttleInterval`.
    private func emitPointer() {

        let now = CACurrentMediaTime()

        guard now - lastEmit >= throttleInterval else {
            return
        }

        lastEmit = now
        onPointerMoved?(NSEvent.mouseLocation)
    }

    @objc
    private func activeDisplayMayHaveChanged() {
        onActiveDisplayMayHaveChanged?()
    }
}
