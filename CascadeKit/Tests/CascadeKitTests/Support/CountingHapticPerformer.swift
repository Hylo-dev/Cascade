//
//  CountingHapticPerformer.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class CountingHapticPerformer: HapticFeedbackPerforming {
    private(set) var count = 0
    func performHoverFeedback() { count += 1 }
}
