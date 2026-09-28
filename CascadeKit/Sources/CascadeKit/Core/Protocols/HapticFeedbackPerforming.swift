//
//  HapticFeedbackPerforming.swift
//  CascadeKit
//

import AppKit

/// HapticFeedbackPerforming isolates the device operation from hover policy.
@MainActor
protocol HapticFeedbackPerforming {
    func performHoverFeedback()
}
