//
//  MusicSpacebarChecks.swift
//  Cascade
//

#if MUSIC_SPACEBAR_TESTS
import AppKit
import os

@main
private enum MusicSpacebarChecks {
    static func main() {
        let toggles = OSAllocatedUnfairLock(initialState: 0)
        let relay = MusicSpacebarRelay { toggles.withLock { $0 += 1 } }
        func key(_ code: CGKeyCode, down: Bool, flags: CGEventFlags = [], repeating: Bool = false) -> CGEvent {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: down)!
            event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: repeating ? 1 : 0)
            return event
        }
        func consumed(_ event: CGEvent) -> Bool { relay.handle(event.type, event) == nil }

        precondition(consumed(key(49, down: true)), "A bare space press is taken from the frontmost app")
        precondition(toggles.withLock { $0 } == 1, "and toggles playback once")
        precondition(consumed(key(49, down: true, repeating: true)), "Holding space is still taken")
        precondition(toggles.withLock { $0 } == 1, "but does not toggle again")
        precondition(consumed(key(49, down: false)), "The release of a taken press is taken too")
        precondition(!consumed(key(49, down: false)), "A release whose press the app saw goes back to it")
        precondition(!consumed(key(49, down: true, flags: .maskCommand)), "Command-space stays Spotlight's")
        precondition(!consumed(key(49, down: true, flags: .maskShift)), "Shift-space passes")
        precondition(!consumed(key(0, down: true)), "Every other key passes")
        precondition(toggles.withLock { $0 } == 1, "None of them toggles")

        // The tap calls its C callback on its own thread. It must run there
        // without a main-actor assertion; this once trapped on the first key.
        let context = Unmanaged.passRetained(relay)
        let done = DispatchSemaphore(value: 0)
        let press = key(49, down: true)
        nonisolated(unsafe) let offMainPress = press
        let reply = OSAllocatedUnfairLock(initialState: true)
        let tapThread = Thread {
            let passed = MusicSpacebarRelay.callback(OpaquePointer(bitPattern: 1)!, .keyDown, offMainPress, context.toOpaque()) != nil
            reply.withLock { $0 = passed }
            done.signal()
        }
        tapThread.start()
        done.wait()
        context.release()
        precondition(reply.withLock { !$0 }, "The callback takes a space on the tap thread")
        precondition(toggles.withLock { $0 } == 2, "and toggles from there")
        checkTapThreadEnds()
        print("Music space bar: 14 behavior checks passed")
    }

    private nonisolated static let noMessages: CFMachPortCallBack = { _, _, _, _ in }

    /// A tap thread must end when its tap stops: invalidating the port alone
    /// left the run loop asleep, one leaked thread per appearance.
    private static func checkTapThreadEnds() {
        func exits(stoppingFirst: Bool) -> Bool {
            let port = CFMachPortCreate(kCFAllocatorDefault, noMessages, nil, nil)!
            let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)!
            let exited = DispatchSemaphore(value: 0)
            let thread = EventTapThread()
            if stoppingFirst { thread.stop() }
            thread.start(name: "check", source: source) { exited.signal() }
            if !stoppingFirst {
                Thread.sleep(forTimeInterval: 0.1)
                CFMachPortInvalidate(port)
                thread.stop()
            }
            return exited.wait(timeout: .now() + 2) == .success
        }
        precondition(exits(stoppingFirst: false), "A stopped tap thread ends instead of sleeping forever")
        precondition(exits(stoppingFirst: true), "A stop that races ahead of the thread still ends it")
    }
}

#endif
