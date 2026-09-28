//
//  HoverFeedback.swift
//  CascadeKit
//

import AppKit

/// HapticFeedbackPerforming isolates the device operation from hover policy.
@MainActor
protocol HapticFeedbackPerforming {
    func performHoverFeedback()
}

/// AppKitHapticPerformer respects the active trackpad and system preferences.
/// The system can suppress a request when no supporting input device is active.
struct AppKitHapticPerformer: HapticFeedbackPerforming {
    func performHoverFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(
            .alignment,
            performanceTime: .now
        )
    }
}

/// HoverFeedback emits at entry, synchronously before the opening animation.
/// Tracking entry even when disabled prevents a delayed impulse if preferences
/// change while the pointer is already inside the notch.
@MainActor
final class HoverFeedback {
    var isEnabled = true
    private var isHovering = false
    private let performer: any HapticFeedbackPerforming

    init(performer: any HapticFeedbackPerforming) {
        self.performer = performer
    }

    func update(isHovering: Bool) {
        let entered = isHovering && !self.isHovering
        self.isHovering = isHovering
        if entered && isEnabled { performer.performHoverFeedback() }
    }
}
