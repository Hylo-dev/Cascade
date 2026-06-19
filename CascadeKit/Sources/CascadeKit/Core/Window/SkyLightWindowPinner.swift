//
//  SkyLightWindowPinner.swift
//  CascadeKit
//

import AppKit
import os

/// SkyLightWindowPinner pins the overlay using Apple's private **SkyLight**
/// framework — the same technique notch apps (e.g. boring.notch) use, because
/// nothing public achieves it.
///
/// The trick is not to fight the window manager but to step outside it: create
/// our *own* SkyLight space at a very high absolute level, show it, and move the
/// panel into it while removing it from every normal space. A window that lives
/// in its own always-shown high space is never slid by a desktop swipe and
/// never sucked into the Mission Control overview — it just stays put.
///
/// This is a deliberately small, audited use of private API. We bind the
/// symbols by hand with `dlopen`/`dlsym`; if a future macOS renames or drops
/// them, binding fails and `pin` becomes a logged no-op (the app still runs,
/// the overlay simply falls back to ordinary `collectionBehavior` behavior).
///
/// Signatures, verbatim from the SkyLight headers:
/// ```c
/// int      SLSMainConnectionID(void);
/// int      SLSSpaceCreate(int cid, int one, int zero);
/// CGError  SLSSpaceSetAbsoluteLevel(int cid, int sid, int level);
/// CGError  SLSShowSpaces(int cid, CFArrayRef spaces);
/// CGError  SLSSpaceAddWindowsAndRemoveFromSpaces(int cid, int sid, CFArrayRef windows, int flags);
/// ```
@MainActor
final class SkyLightWindowPinner: WindowPinning {

    private typealias MainConnectionID              = @convention(c) () -> Int32
    private typealias SpaceCreate                   = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias SpaceSetAbsoluteLevel         = @convention(c) (Int32, Int32, Int32) -> Int32
    private typealias ShowSpaces                    = @convention(c) (Int32, CFArray) -> Int32
    private typealias AddWindowsAndRemoveFromSpaces = @convention(c) (Int32, Int32, CFArray, Int32) -> Int32

    /// Absolute z-level of our private space. 400 (`NotificationCenterAtScreenLock`)
    /// is what boring.notch uses: high enough to float above Mission Control and
    /// the menu bar. It also floats above the lock screen — lower this if the
    /// notch should hide while locked.
    private static let spaceLevel: Int32 = 400

    /// Flag passed to `SLSSpaceAddWindowsAndRemoveFromSpaces`; `7` is the value
    /// the SkyLight community wrappers use to move-and-remove in one call.
    private static let addAndRemoveFlags: Int32 = 7

    private let connection: Int32
    private let space     : Int32
    private let addToSpace : AddWindowsAndRemoveFromSpaces?

    private let log = Logger(subsystem: "hylo.Cascade", category: "SkyLight")

    init() {

        guard
            let handle  = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight", RTLD_NOW),
            let pConn   = dlsym(handle, "SLSMainConnectionID"),
            let pCreate = dlsym(handle, "SLSSpaceCreate"),
            let pLevel  = dlsym(handle, "SLSSpaceSetAbsoluteLevel"),
            let pShow   = dlsym(handle, "SLSShowSpaces"),
            let pAdd    = dlsym(handle, "SLSSpaceAddWindowsAndRemoveFromSpaces")
        else {
            self.connection = 0
            self.space      = 0
            self.addToSpace = nil
            return
        }

        let mainConnectionID = unsafeBitCast(pConn,   to: MainConnectionID.self)
        let spaceCreate      = unsafeBitCast(pCreate, to: SpaceCreate.self)
        let setAbsoluteLevel = unsafeBitCast(pLevel,  to: SpaceSetAbsoluteLevel.self)
        let showSpaces       = unsafeBitCast(pShow,   to: ShowSpaces.self)

        let connection = mainConnectionID()
        let space      = spaceCreate(connection, 1, 0)

        _ = setAbsoluteLevel(connection, space, Self.spaceLevel)
        _ = showSpaces(connection, [space] as CFArray)

        self.connection = connection
        self.space      = space
        self.addToSpace = unsafeBitCast(pAdd, to: AddWindowsAndRemoveFromSpaces.self)
    }

    func pin(_ window: NSWindow) {

        guard let addToSpace, space != 0 else {
            log.error("SkyLight unavailable — overlay left on ordinary window levels")
            return
        }

        _ = addToSpace(
            connection,
            space,
            [window.windowNumber] as CFArray,
            Self.addAndRemoveFlags
        )
    }
}
