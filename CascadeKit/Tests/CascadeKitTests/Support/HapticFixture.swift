//
//  HapticFixture.swift
//  CascadeKit
//

import Testing
@testable import CascadeKit

@MainActor
final class HapticFixture: HapticFeedbackPerforming {
    var impulses = 0
    func performHoverFeedback() { impulses += 1 }
}
