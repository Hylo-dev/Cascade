//
//  SpotlightDisplayAnchor.swift
//  Cascade
//

import AppKit

/// SpotlightDisplayAnchor freezes the invocation display and its actual compact
/// surface before focus can move to the native Spotlight window.
@MainActor
struct SpotlightDisplayAnchor {
    let displayID    : CGDirectDisplayID
    let screen       : NSScreen
    let restingBounds: CGRect
}
