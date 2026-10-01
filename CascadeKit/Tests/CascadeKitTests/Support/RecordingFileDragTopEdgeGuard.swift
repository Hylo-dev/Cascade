//
//  RecordingFileDragTopEdgeGuard.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class RecordingFileDragTopEdgeGuard: FileDragTopEdgeGuardOperating {
    private(set) var availability: FileDragTopEdgeGuard.Availability = .inactive
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start(region: CGRect, screen: CGRect) -> Bool {
        startCount += 1
        availability = .active
        return true
    }

    func update(region: CGRect, screen: CGRect) {}

    func stop() {
        stopCount += 1
        if availability != .unavailable { availability = .inactive }
    }
}
