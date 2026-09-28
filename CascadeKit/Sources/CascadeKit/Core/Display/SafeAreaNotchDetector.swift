//
//  SafeAreaNotchDetector.swift
//  CascadeKit
//

import AppKit

/// SafeAreaNotchDetector is the single-controller pointer fallback from before
/// the display coordinator, which now takes its displays from `DisplayInventory`.
///
/// Focused-window ownership is deliberately absent here. Keeping focus in the
/// pure resolver prevents this legacy adapter from competing with the new AX
/// monitor or with `DisplayInventory`.
final class SafeAreaNotchDetector: ActiveDisplayResolving {

    func resolveActiveDisplay() -> ActiveDisplay? {
        let pointer = NSEvent.mouseLocation
        let screen  = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) }
                   ?? NSScreen.main

        return screen?.activeDisplaySnapshot()
    }
}
