//
//  ActiveDisplay.swift
//  CascadeKit
//

import CoreGraphics

/// ActiveDisplay is a snapshot of the screen Cascade is currently following.
///
/// It is a value type on purpose: the resolver reads AppKit once and hands the
/// engine an immutable description, so the positioning math never has to
/// re-enter AppKit, and two snapshots can be compared cheaply by `displayID` to
/// decide whether the active screen actually changed (the coalescing that keeps
/// the panel from being re-placed on every mouse twitch).
nonisolated struct ActiveDisplay: Equatable, Sendable {

    let displayID    : CGDirectDisplayID
    let frame        : CGRect        // Full screen frame, AppKit global coordinates.
    let backingScale : CGFloat
    let notch        : HardwareNotch

    /// Whether the followed screen has a physical notch — and therefore whether
    /// we draw the chrome. The interactive zone exists regardless of this.
    var hasHardwareNotch: Bool {
        notch.isPresent
    }
}
