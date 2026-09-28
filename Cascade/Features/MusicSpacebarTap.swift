//
//  MusicSpacebarTap.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices

/// MusicSpacebarTap makes the space bar the play/pause button while the
/// expanded player is on screen. The notch never becomes key, so it cannot
/// receive the key itself; a Quartz tap takes it instead, and only between the
/// expanded player's appearance and disappearance: a closed notch has no tap.
///
/// The tap runs on its own thread and decides from the key alone, so typing
/// elsewhere never waits on Cascade's main thread; the toggle reaches the main
/// actor after the keystroke has been consumed. A bare space is taken, key up
/// included; shortcuts with modifiers pass through. Like the Spotlight and
/// volume taps it needs Accessibility; without it the tap cannot be created and
/// the space bar keeps its ordinary meaning.
@MainActor
final class MusicSpacebarTap {
    var onToggle: (() -> Void)?
    private var port: CFMachPort?
    private var thread: EventTapThread?

    func start() {
        guard port == nil else { return }
        let relay = MusicSpacebarRelay { [weak self] in
            Task { @MainActor [weak self] in self?.onToggle?() }
        }
        let context = Unmanaged.passRetained(relay)
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        guard let port = CGEvent.tapCreate(
            tap             : .cgSessionEventTap,
            place           : .headInsertEventTap,
            options         : .defaultTap,
            eventsOfInterest: mask,
            callback        : MusicSpacebarRelay.callback,
            userInfo        : context.toOpaque()
        ),
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0) else {
            context.release()
            return
        }
        relay.port = port
        self.port = port
        // The relay is released on the tap thread once its run loop has
        // returned, when no callback is left to run.
        let thread = EventTapThread()
        thread.start(name: "Cascade.MusicSpacebar", source: source) { context.release() }
        self.thread = thread
        CGEvent.tapEnable(tap: port, enable: true)
    }

    func stop() {
        if let port { CFMachPortInvalidate(port) }
        port = nil
        thread?.stop()
        thread = nil
    }

    isolated deinit {
        stop()
    }
}

/// MusicSpacebarRelay is the tap thread's side. Every callback runs on that
/// one thread, so its state needs no lock.
nonisolated final class MusicSpacebarRelay: @unchecked Sendable {
    /// callback is the tap's C function. It must be written outside the main
    /// actor: with main-actor default isolation, a closure literal inside
    /// `start()` is main-actor isolated and Swift asserts that isolation on
    /// entry, so the tap thread's first keystroke trapped in libdispatch
    /// while the tap, left installed, held every keystroke system-wide.
    static let callback: CGEventTapCallBack = { _, type, event, context in
        guard let context else { return Unmanaged.passUnretained(event) }
        return Unmanaged<MusicSpacebarRelay>.fromOpaque(context)
            .takeUnretainedValue()
            .handle(type, event)
    }

    private static let spaceKeyCode: Int64 = 49
    private static let modifiers: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn]

    let toggle: @Sendable () -> Void
    var port: CFMachPort?
    private var holdsSpace = false

    init(toggle: @escaping @Sendable () -> Void) {
        self.toggle = toggle
    }

    func handle(_ type: CGEventType, _ event: CGEvent) -> Unmanaged<CGEvent>? {
        let isSpace = event.getIntegerValueField(.keyboardEventKeycode) == Self.spaceKeyCode
        switch type {
        case .tapDisabledByTimeout:
            if let port { CGEvent.tapEnable(tap: port, enable: true) }
        case .keyDown where isSpace && event.flags.intersection(Self.modifiers).isEmpty:
            holdsSpace = true
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 { toggle() }
            return nil
        case .keyUp where isSpace && holdsSpace:
            // Only the release of a press this tap took; any other one belongs
            // to the application that saw its press.
            holdsSpace = false
            return nil
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }
}
