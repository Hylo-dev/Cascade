//
//  RecordingSpotlightTap.swift
//  Cascade
//

import AppKit
import CascadeKit
import Testing
@testable import Cascade

@MainActor
final class RecordingSpotlightTap: SpotlightKeyTapping {
    private(set) var nativeInvocationCount = 0

    func start(
        handler   : @escaping (CGEventType, CGEvent) -> Bool,
        onDisabled: @escaping () -> Void
    ) -> Bool { true }
    func stop() {}
    var isActive: Bool { true }
    func updateGate(keyCode: CGKeyCode?, isEngaged: Bool) {}
    func invokeNative(_ shortcut: SpotlightShortcut) { nativeInvocationCount += 1 }
    func deliver(_ events: [CGEvent], to processID: pid_t) {}
}
