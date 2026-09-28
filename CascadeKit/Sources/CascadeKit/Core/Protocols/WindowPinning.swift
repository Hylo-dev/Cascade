//
//  WindowPinning.swift
//  CascadeKit
//

import AppKit

/// WindowPinning keeps a window *put*: visible and un-animated across Space
/// switches and Mission Control, the way the menu bar is.
///
/// This is the one thing public AppKit cannot do — `collectionBehavior`
/// (`.canJoinAllSpaces` + `.stationary`) makes a window appear everywhere but
/// it still slides with a desktop swipe and gets pulled into the Mission
/// Control overview. The only way to truly pin it is below the public API, so
/// the capability lives behind this protocol: the engine depends on the
/// contract, and the private-API implementation is a small, swappable, audited
/// blast radius (a no-op stub satisfies it in tests).
@MainActor
protocol WindowPinning {

    /// Pin `window` so a desktop swipe and Mission Control leave it where it is.
    /// Call once, after the window has been ordered on screen (it needs a valid
    /// `windowNumber`).
    func pin(_ window: NSWindow)
}
