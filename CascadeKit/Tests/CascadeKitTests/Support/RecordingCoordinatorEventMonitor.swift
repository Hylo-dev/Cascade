//
//  RecordingCoordinatorEventMonitor.swift
//  CascadeKit
//

import AppKit
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class RecordingCoordinatorEventMonitor: EventMonitoring {
    var onPointerMoved               : ((CGPoint) -> Void)?
    var onPointerButtonChanged       : ((Bool) -> Void)?
    var onActiveDisplayMayHaveChanged: (() -> Void)?
    var onSpaceChanged               : (() -> Void)?
    var onScreenLocked               : (() -> Void)?
    var onScreenUnlocked             : (() -> Void)?
    var onScreensAsleepChanged       : ((Bool) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var fileDragRecognitionHandler: ((Bool, CGPoint, Bool) -> Void)?
    func start() { startCount += 1 }
    func stop() { stopCount += 1 }
    func sendLock() { onScreenLocked?() }
    func sendUnlock() { onScreenUnlocked?() }
    func sendScreensAsleep(_ asleep: Bool) { onScreensAsleepChanged?(asleep) }
    func sendPointer(_ point: CGPoint) { onPointerMoved?(point) }
    func sendButton(isPressed: Bool) { onPointerButtonChanged?(isPressed) }
    func setFileDragRecognitionHandler(_ handler: ((Bool, CGPoint, Bool) -> Void)?) {
        fileDragRecognitionHandler = handler
    }
    func sendRecognizedFileDrag(
        active: Bool,
        point: CGPoint,
        hasValidatedOfferHint: Bool = false
    ) {
        fileDragRecognitionHandler?(active, point, hasValidatedOfferHint)
    }
}
