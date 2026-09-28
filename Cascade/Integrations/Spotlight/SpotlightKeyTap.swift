//
//  SpotlightKeyTap.swift
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

/// SpotlightKeyGate is the tap thread's lock-protected view of the only two
/// facts that decide whether a keystroke concerns Spotlight: the shortcut's key
/// and whether a handoff or the native field is live. Everything else is plain
/// typing and passes without ever waiting on Cascade's main thread.
nonisolated final class SpotlightKeyGate: Sendable {
    private struct State {
        var keyCode  : Int64?
        var isEngaged = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func update(keyCode: CGKeyCode?, isEngaged: Bool) {
        state.withLock { $0 = State(keyCode: keyCode.map(Int64.init), isEngaged: isEngaged) }
    }

    /// needsDecision is one lock and two compares: allocation-free on the tap
    /// thread, and conservative, since the main actor still has the last word.
    func needsDecision(_ event: CGEvent) -> Bool {
        let key = event.getIntegerValueField(.keyboardEventKeycode)
        return state.withLock { state in
            guard let keyCode = state.keyCode else { return false }
            return state.isEngaged || key == keyCode
        }
    }
}

/// SpotlightKeyTap keeps its Quartz tap on a dedicated run-loop thread, so a
/// busy main thread never delays typing system-wide. The gate passes ordinary
/// keys on that thread; only the shortcut key and keys during a live handoff
/// are decided synchronously on the main actor, whose handler only examines a
/// key and retains a bounded event copy. Animation, AX messaging and system
/// invocation stay scheduled outside the callback.
@MainActor
final class SpotlightKeyTap: SpotlightKeyTapping {
    nonisolated static let replayMarker: Int64 = 0x4341534353504F54
    nonisolated let gate = SpotlightKeyGate()
    private var port: CFMachPort?
    private var thread: EventTapThread?
    private var handler: ((CGEventType, CGEvent) -> Bool)?
    private var onDisabled: (() -> Void)?

    func start(handler: @escaping (CGEventType, CGEvent) -> Bool, onDisabled: @escaping () -> Void) -> Bool {
        stop()
        self.handler = handler
        self.onDisabled = onDisabled
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .defaultTap, eventsOfInterest: mask, callback: Self.callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()),
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            self.handler = nil
            self.onDisabled = nil
            return false
        }
        self.port = port
        // One thread per installed tap, ended by stop.
        let thread = EventTapThread()
        thread.start(name: "Cascade.SpotlightKeys", source: source)
        self.thread = thread
        CGEvent.tapEnable(tap: port, enable: true)
        return CGEvent.tapIsEnabled(tap: port)
    }

    /// callback runs on the tap thread, so it is written outside the main
    /// actor. As a closure literal inside `start()` it was main-actor isolated
    /// and Swift asserted that on entry: the first keystroke on the tap thread
    /// trapped in libdispatch. The app owner retains this tap, and stop
    /// invalidates the port before clearing the handler.
    nonisolated static let callback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        let owner = Unmanaged<SpotlightKeyTap>.fromOpaque(context).takeUnretainedValue()
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            DispatchQueue.main.async { MainActor.assumeIsolated { owner.onDisabled?() } }
            return Unmanaged.passUnretained(event)
        }
        guard event.getIntegerValueField(.eventSourceUserData) != SpotlightKeyTap.replayMarker,
              owner.gate.needsDecision(event) else {
            return Unmanaged.passUnretained(event)
        }
        // Main never waits on this thread (stop only invalidates), so this
        // rare synchronous hop cannot deadlock. The tap thread is blocked in
        // it, so the event is only ever touched by one thread at a time.
        nonisolated(unsafe) let decided = event
        let suppress = DispatchQueue.main.sync {
            MainActor.assumeIsolated { owner.handler?(type, decided) == true }
        }
        return suppress ? nil : Unmanaged.passUnretained(event)
    }

    func stop() {
        if let port { CFMachPortInvalidate(port) }
        port = nil
        thread?.stop()
        thread = nil
        handler = nil
        onDisabled = nil
    }

    func updateGate(keyCode: CGKeyCode?, isEngaged: Bool) {
        gate.update(keyCode: keyCode, isEngaged: isEngaged)
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
