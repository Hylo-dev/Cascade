//
//  ScreenshotKeyGate.swift
//  Cascade
//

import CoreGraphics
import os

/// ScreenshotKeyGate decides suppression entirely on the tap thread. Two fixed
/// bitsets retain consumed presses until release, even if modifiers change first;
/// a held key opens the notch once. Ordinary input never waits for the UI thread.
nonisolated final class ScreenshotKeyGate: Sendable {

    enum Decision {

        case pass
        case suppress
        case open
        case cancel
    }

    private struct State {

        var shortcuts: ScreenshotShortcuts?
        var lowKeys  : UInt64 = 0
        var highKeys : UInt64 = 0
        var cancellationEnabled = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    func update(shortcuts: ScreenshotShortcuts?) {
        state.withLock { $0 = State(shortcuts: shortcuts) }
    }

    /// setCancellationEnabled changes modal ownership without forgetting held
    /// presses. Escape's release is still swallowed after its close action.
    func setCancellationEnabled(_ isEnabled: Bool) {
        state.withLock { $0.cancellationEnabled = isEnabled }
    }

    /// consume bounds-checks the key before shifting. The fixed storage covers
    /// all 128 macOS virtual keys and is mutated only under this short lock.
    func consume(
        type : CGEventType,
        event: CGEvent
    ) -> Decision {
        guard type == .keyDown || type == .keyUp else { return .pass }

        let key = event.getIntegerValueField(.keyboardEventKeycode)
        guard key >= 0, key < 128 else { return .pass }

        let bit = UInt64(1) << UInt64(key & 63)
        let flags = event.flags
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        return state.withLock { state in
            guard let shortcuts = state.shortcuts else { return .pass }

            let isHeld = (key < 64 ? state.lowKeys : state.highKeys) & bit != 0
            if type == .keyUp {
                if key < 64 { state.lowKeys &= ~bit }
                else { state.highKeys &= ~bit }
                return isHeld ? .suppress : .pass
            }
            if isHeld { return .suppress }
            let isCancellation = key == 53 && state.cancellationEnabled
                && flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate]).isEmpty
            guard isCancellation || shortcuts.matches(keyCode: CGKeyCode(key), flags: flags)
            else { return .pass }

            if key < 64 { state.lowKeys |= bit }
            else { state.highKeys |= bit }
            if isRepeat { return .suppress }
            return isCancellation ? .cancel : .open
        }
    }
}
