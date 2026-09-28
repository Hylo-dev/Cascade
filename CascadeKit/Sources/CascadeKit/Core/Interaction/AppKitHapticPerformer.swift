//
//  AppKitHapticPerformer.swift
//  CascadeKit
//

import AppKit

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
