//
//  RecordingEventMonitor.swift
//  CascadeKit
//

import AppKit
import QuartzCore
import SwiftUI
import Testing
@testable import CascadeKit

@MainActor
final class RecordingEventMonitor: EventMonitoring {

    var onPointerMoved               : ((CGPoint) -> Void)?
    var onPointerButtonChanged       : ((Bool) -> Void)?
    var onActiveDisplayMayHaveChanged: (() -> Void)?
    var onSpaceChanged               : (() -> Void)?
    var onScreenLocked               : (() -> Void)?
    var onScreenUnlocked             : (() -> Void)?
    var onScreensAsleepChanged       : ((Bool) -> Void)?

    func start() {}

    func stop() {}

    func sendPointer(_ point: CGPoint) { onPointerMoved?(point) }

    func sendButton(isPressed: Bool) { onPointerButtonChanged?(isPressed) }

    func sendDisplayChange() { onActiveDisplayMayHaveChanged?() }

    func sendLock() { onScreenLocked?() }

    func sendUnlock() { onScreenUnlocked?() }
}
