//
//  SpotlightKeyTapping.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import os

@MainActor
protocol SpotlightKeyTapping: AnyObject {
    func start(
        handler   : @escaping (CGEventType, CGEvent) -> Bool,
        onDisabled: @escaping () -> Void
    ) -> Bool
    func stop()
    var isActive: Bool { get }
    func updateGate(keyCode: CGKeyCode?, isEngaged: Bool)
    func invokeNative(_ shortcut: SpotlightShortcut)
    func deliver(_ events: [CGEvent], to processID: pid_t)
}
