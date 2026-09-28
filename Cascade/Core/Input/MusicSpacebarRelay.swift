//
//  MusicSpacebarRelay.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices

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

    private static let spaceKeyCode: Int64        = 49
    private static let modifiers   : CGEventFlags = [
        .maskCommand,
        .maskControl,
        .maskAlternate,
        .maskShift,
        .maskSecondaryFn
    ]

    let toggle: @Sendable () -> Void
    var port  : CFMachPort?

    private var holdsSpace = false

    init(toggle: @escaping @Sendable () -> Void) {
        self.toggle = toggle
    }

    func handle(
        _ type : CGEventType,
        _ event: CGEvent
    ) -> Unmanaged<CGEvent>? {
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
