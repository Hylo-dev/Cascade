//
//  SpotlightKeyGate.swift
//  Cascade
//

import AppKit
@preconcurrency import ApplicationServices
import os

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
