//
//  EventTapThread.swift
//  Cascade
//

import Foundation
import os

/// EventTapThread runs one event tap's run-loop source on a dedicated thread,
/// so a busy main thread never delays typing system-wide, and ends that thread
/// when the tap stops.
///
/// Invalidating the tap's port alone is not enough: it removes the source, but
/// the run loop stays asleep in `mach_msg` with nothing left to wake it, so the
/// thread and whatever it retains lived forever. The space-bar tap left one
/// such thread behind for every time the expanded player appeared. `stop`
/// therefore also stops the run loop. A stop that races ahead of the thread is
/// covered too: the thread then either sees the flag or finds its invalidated
/// source already gone, and returns at once.
nonisolated final class EventTapThread: @unchecked Sendable {
    private struct State {
        var runLoop  : CFRunLoop?
        var isStopped = false
    }

    private let state = OSAllocatedUnfairLock(uncheckedState: State())

    /// start adds `source` to a new thread's run loop and runs it until
    /// `stop`. `onExit` runs on that thread after its last callback.
    func start(
        name  : String,
        source: CFRunLoopSource,
        onExit: @escaping @Sendable () -> Void = {}
    ) {
        nonisolated(unsafe) let source = source
        let thread = Thread { [state] in
            let runLoop = CFRunLoopGetCurrent()
            let proceeds = state.withLockUnchecked { state -> Bool in
                guard !state.isStopped else { return false }
                state.runLoop = runLoop
                return true
            }
            if proceeds {
                CFRunLoopAddSource(runLoop, source, .defaultMode)
                CFRunLoopRun()
            }
            state.withLockUnchecked { $0.runLoop = nil }
            onExit()
        }
        thread.name = name
        thread.qualityOfService = .userInteractive
        thread.start()
    }

    /// stop wakes and ends the thread's run loop. Call it after invalidating
    /// the tap's port, so no callback can arrive once the loop has returned.
    func stop() {
        let runLoop = state.withLockUnchecked { state -> CFRunLoop? in
            state.isStopped = true
            return state.runLoop
        }
        if let runLoop { CFRunLoopStop(runLoop) }
    }
}
