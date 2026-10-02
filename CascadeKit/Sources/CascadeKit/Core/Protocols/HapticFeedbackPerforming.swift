//
//  HapticFeedbackPerforming.swift
//  CascadeKit
//

/// HapticFeedbackPerforming isolates the device operation from hover policy.
@MainActor
protocol HapticFeedbackPerforming {

    func performHoverFeedback()

    /// performSnapFeedback marks something settling into place, such as a dragged widget
    /// reaching a new cell.
    func performSnapFeedback()
}

extension HapticFeedbackPerforming {

    func performSnapFeedback() {
        performHoverFeedback()
    }
}
