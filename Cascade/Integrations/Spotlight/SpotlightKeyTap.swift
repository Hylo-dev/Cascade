//
//  SpotlightKeyTap.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices

@MainActor
protocol SpotlightKeyTapping: AnyObject {
    func start(
        handler   : @escaping (CGEventType, CGEvent) -> Bool,
        onDisabled: @escaping () -> Void
    ) -> Bool
    func stop()
    var isActive: Bool { get }
    func invokeNative(_ shortcut: SpotlightShortcut)
    func deliver(_ events: [CGEvent], to processID: pid_t)
}

/// SpotlightKeyTap synchronously decides pass/suppress on the main run loop.
/// Its handler only examines a key and retains a bounded event copy; animation,
/// AX messaging, and system invocation are scheduled outside the callback.
@MainActor
final class SpotlightKeyTap: SpotlightKeyTapping {
    static let replayMarker: Int64 = 0x4341534353504F54
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    private var handler: ((CGEventType, CGEvent) -> Bool)?
    private var onDisabled: (() -> Void)?

    func start(handler: @escaping (CGEventType, CGEvent) -> Bool, onDisabled: @escaping () -> Void) -> Bool {
        stop()
        self.handler = handler
        self.onDisabled = onDisabled
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                // The source is installed only on CFRunLoopGetMain. Invalidation
                // precedes clearing the handler; the app owner retains this tap.
                let suppress = MainActor.assumeIsolated {
                    let owner = Unmanaged<SpotlightKeyTap>.fromOpaque(context).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        owner.onDisabled?()
                        return false
                    }
                    guard event.getIntegerValueField(.eventSourceUserData) != SpotlightKeyTap.replayMarker else {
                        return false
                    }
                    return owner.handler?(type, event) == true
                }
                return suppress ? nil : Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            self.handler = nil
            self.onDisabled = nil
            return false
        }
        self.port = port
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        return CGEvent.tapIsEnabled(tap: port)
    }

    func stop() {
        if let port { CFMachPortInvalidate(port) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        port = nil
        source = nil
        handler = nil
        onDisabled = nil
    }

    var isActive: Bool { port.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }

    /// invokeNative posts the configured system shortcut with a marker that
    /// prevents our own tap from delaying its replay for a second time.
    func invokeNative(_ shortcut: SpotlightShortcut) {
        for isDown in [true, false] {
            guard let event = CGEvent(keyboardEventSource: nil, virtualKey: shortcut.keyCode, keyDown: isDown) else { continue }
            event.flags = shortcut.flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
            event.post(tap: .cghidEventTap)
        }
    }

    /// deliver routes retained input only to the verified native process. It
    /// never releases search keystrokes globally into the previous application.
    func deliver(_ events: [CGEvent], to processID: pid_t) {
        for event in events {
            event.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
            event.postToPid(processID)
        }
    }
}
