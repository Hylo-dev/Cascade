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

    /// Fired when app activation or screen layout should make the legacy single
    /// controller refresh its pointer snapshot. It carries no focus geometry;
    /// focused-window ownership belongs to FocusedWindowMonitor.
    var onActiveDisplayMayHaveChanged: (() -> Void)? { get set }

    /// Fired when the active Space changes — this covers both a desktop swipe
    /// (notch should stay open) and Mission Control opening (notch should close).
    /// The controller disambiguates the two; the monitor just reports the event.
    var onSpaceChanged: (() -> Void)? { get set }

    /// Fired when the screen locks / unlocks. The overlay hides while locked so
    /// it never appears on the login / lock screen, and comes back on unlock.
    var onScreenLocked  : (() -> Void)? { get set }
    var onScreenUnlocked: (() -> Void)? { get set }

    func start()
    func stop()
}
