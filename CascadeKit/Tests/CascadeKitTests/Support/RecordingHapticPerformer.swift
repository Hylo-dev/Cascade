//
//  RecordingHapticPerformer.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
struct RecordingHapticPerformer: HapticFeedbackPerforming {
    let onPerform: () -> Void
    func performHoverFeedback() { onPerform() }
}
