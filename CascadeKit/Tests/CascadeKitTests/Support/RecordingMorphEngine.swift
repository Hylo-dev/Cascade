//
//  RecordingMorphEngine.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class RecordingMorphEngine: MorphEngineDriving {

    private(set) var isRunning  = false
    private(set) var startCount = 0

    private let onStart: () -> Void
    private var onFrame: ((CFTimeInterval) -> Void)?

    init(onStart: @escaping () -> Void = {}) {
        self.onStart = onStart
    }

    func start(onFrame: @escaping (CFTimeInterval) -> Void) {
        guard !isRunning else { return }

        isRunning    = true
        self.onFrame = onFrame
        startCount  += 1
        onStart()
    }

    func stop() {
        isRunning = false
        onFrame   = nil
    }

    func tick() { onFrame?(1.0 / 120.0) }

    func settle() { for _ in 0..<600 where isRunning { tick() } }
}
