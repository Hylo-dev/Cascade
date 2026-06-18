//
//  EventMonitoring.swift
//  CascadeKit
//

import CoreGraphics

/// EventMonitoring watches the system for the few signals the notch cares
/// about, and reports them as cheap callbacks.
///
/// It is a protocol so the controller can be tested without a real event
/// stream. The contract is intentionally tiny: a coalesced pointer position and
/// a "the active screen may have changed" nudge. The controller decides what to
/// do with them — the monitor never reaches into the notch state itself.
protocol EventMonitoring: AnyObject {

    /// Throttled pointer position, in AppKit global (bottom-left) coordinates.
    var onPointerMoved: ((CGPoint) -> Void)? { get set }

    /// Fired when the active app changes or the screen layout changes — both
    /// reasons to re-resolve which display we should be following.
    var onActiveDisplayMayHaveChanged: (() -> Void)? { get set }

    func start()
    func stop()
}
