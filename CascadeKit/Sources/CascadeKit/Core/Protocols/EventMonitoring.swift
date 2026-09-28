//
//  EventMonitoring.swift
//  CascadeKit
//

import CoreGraphics

/// EventMonitoring watches the system once for the process and reports the few
/// signals the display coordinator needs as cheap callbacks.
///
/// It is a protocol so the controller can be tested without a real event
/// stream. The contract is intentionally tiny: a coalesced pointer position and
/// a "focus may have changed" nudge. The coordinator routes each event to the
/// pointed surface plus the previous/current owner; local panels never install
/// competing global monitors.
protocol EventMonitoring: AnyObject {

    /// Throttled pointer position, in AppKit global (bottom-left) coordinates.
    var onPointerMoved: ((CGPoint) -> Void)? { get set }

    /// Fired for mouse-button transitions. The controller uses this only to
    /// retain panel interception through a control drag that began in the live
    /// path; it does not interpret buttons or synthesize clicks.
    var onPointerButtonChanged: ((Bool) -> Void)? { get set }

    /// Fired when app activation or screen layout may have moved the active
    /// display. The display coordinator answers it by refreshing its
    /// focused-window monitor. It carries no focus geometry; focused-window
    /// ownership belongs to FocusedWindowMonitor.
    var onActiveDisplayMayHaveChanged: (() -> Void)? { get set }

    /// Fired when the active Space changes — this covers both a desktop swipe
    /// (notch should stay open) and Mission Control opening (notch should close).
    /// The controller disambiguates the two; the monitor just reports the event.
    var onSpaceChanged: (() -> Void)? { get set }

    /// Fired when the screen locks / unlocks. The overlay hides while locked so
    /// it never appears on the login / lock screen, and comes back on unlock.
    var onScreenLocked  : (() -> Void)? { get set }
    var onScreenUnlocked: (() -> Void)? { get set }

    /// Fired with `true` when every display goes to sleep and `false` when they
    /// wake. Display sleep does not lock the session, so without this signal a
    /// playing track keeps its audio tap and 30 Hz spectrum running for a dark
    /// screen. It is independent of lock: waking a locked screen stays hidden.
    var onScreensAsleepChanged: ((Bool) -> Void)? { get set }

    /// Installs the gesture-bound file-drag signal. The first Bool is true once
    /// for a freshly populated native drag pasteboard and false at its end. The
    /// second Bool is a fresh, stable regular-file hint for early UI routing;
    /// it never authorizes a drop.
    func setFileDragRecognitionHandler(_ handler: ((Bool, CGPoint, Bool) -> Void)?)

    func start()
    func stop()
}

extension EventMonitoring {
    func setFileDragRecognitionHandler(_ handler: ((Bool, CGPoint, Bool) -> Void)?) {}
}
