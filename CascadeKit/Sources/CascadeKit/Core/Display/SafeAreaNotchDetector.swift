//
//  SafeAreaNotchDetector.swift
//  CascadeKit
//

import AppKit

/// SafeAreaNotchDetector resolves the active display from AppKit.
///
/// "Active" means the screen under the pointer — the place the user is looking —
/// falling back to the main screen. We resolve from the mouse rather than the
/// key window on purpose: Cascade is a nonactivating overlay that never holds
/// focus, so there is often no key window of ours to ask.
final class SafeAreaNotchDetector: ActiveDisplayResolving {

    func resolveActiveDisplay() -> ActiveDisplay? {

        let pointer = NSEvent.mouseLocation
        let screen  = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
                   ?? NSScreen.main

        return screen?.activeDisplaySnapshot()
    }
}
