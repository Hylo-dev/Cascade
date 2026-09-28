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

    private var port  : CFMachPort?
    private var thread: EventTapThread?

    func start() {
        guard port == nil else { return }

        let relay = MusicSpacebarRelay { [weak self] in
            Task { @MainActor [weak self] in self?.onToggle?() }
        }
        let context = Unmanaged.passRetained(relay)
        let keyEventMask = (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)

        guard let port = CGEvent.tapCreate(
            tap             : .cgSessionEventTap,
            place           : .headInsertEventTap,
            options         : .defaultTap,
            eventsOfInterest: keyEventMask,
            callback        : MusicSpacebarRelay.callback,
            userInfo        : context.toOpaque()
        ),
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        else {
            context.release()
            return
        }

        relay.port = port
        self.port  = port

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
