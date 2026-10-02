//
//  AppKitHapticPerformer.swift
//  CascadeKit
//

import AppKit

/// AppKitHapticPerformer respects the active trackpad and system preferences.
/// The system can suppress a request when no supporting input device is active.
struct AppKitHapticPerformer: HapticFeedbackPerforming {

    func performHoverFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    /// performSnapFeedback uses the alignment pattern macOS itself plays when something snaps.
    func performSnapFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }
}
