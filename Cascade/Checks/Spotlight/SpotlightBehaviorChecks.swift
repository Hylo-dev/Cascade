//
//  SpotlightBehaviorChecks.swift
//  Cascade
//

#if SPOTLIGHT_BEHAVIOR_TESTS
import AppKit
import Foundation

@main
struct SpotlightBehaviorChecks {

    static func main() {
        var gate = SpotlightHandoffState()
        let first = gate.begin()!
        precondition(gate.begin() == nil, "A held shortcut must not start a second droplet")
        precondition(gate.shouldBufferInput, "Typing during the delayed reveal must be retained")
        precondition(
            !gate.acceptNativeReady(generation: first),
            "Native cannot take ownership before invocation"
        )
        precondition(
            gate.requestNative(generation: first),
            "The completed drop must invoke native search once"
        )
        precondition(
            !gate.requestNative(generation: first),
            "Duplicate completion must not toggle Spotlight closed"
        )
        precondition(gate.acceptNativeReady(generation: first))
        precondition(!gate.shouldBufferInput, "Typing must pass through once native focus is ready")

        precondition(
            gate.begin() == nil,
            "An already visible search must close before opening again"
        )
        gate.nativeWillClose()
        let cancelled = gate.begin()!
        gate.cancel()
        precondition(
            !gate.requestNative(generation: cancelled),
            "Cancelled animation must never reopen Spotlight"
        )
        let current = gate.begin()!
        precondition(
            !gate.acceptNativeReady(generation: cancelled),
            "A previous AX response cannot finish a new opening"
        )
        precondition(gate.requestNative(generation: current))
        gate.cancel()
        precondition(!gate.shouldBufferInput, "Timeout/disable must release the keyboard gate")

        var rapid = SpotlightHandoffState()
        let opening = rapid.begin()!
        precondition(rapid.requestNative(generation: opening))
        precondition(rapid.acceptNativeReady(generation: opening))
        rapid.nativeWillClose()
        let reopening = rapid.begin()
        precondition(
            reopening != nil,
            "Closing must permit another droplet before AX reports that the window disappeared"
        )
        rapid.observeNative(isVisible: true, generation: opening)
        precondition(
            rapid.shouldBufferInput,
            "Stale visible events must not bypass the new animation"
        )
        rapid.observeNative(isVisible: false, generation: opening)
        precondition(
            rapid.requestNative(generation: reopening!),
            "A delayed close event must not cancel a new opening"
        )
        rapid.nativeWillClose()
        precondition(
            !rapid.shouldBufferInput,
            "Closing during native launch must release buffered input immediately"
        )
        precondition(rapid.begin() != nil, "Open-close-open must also restart during native launch")

        var escape = SpotlightHandoffState()
        let beforeEscape = escape.begin()!
        precondition(escape.requestNative(generation: beforeEscape))
        precondition(escape.acceptNativeReady(generation: beforeEscape))
        escape.nativeMayDismiss()
        let reservedToggle = escape.reserveToggleAfterPossibleDismissal()
        precondition(
            reservedToggle != nil && escape.shouldBufferInput,
            "Escape followed by a shortcut must reserve a fresh decision before delayed AXHidden"
        )
        precondition(
            !escape.acceptNativeReady(generation: beforeEscape),
            "The previous visible window cannot complete the reserved reopening"
        )

        escape.cancel()
        escape.observeNative(isVisible: true, generation: escape.generation)
        precondition(
            escape.nativeIsVisible,
            "After an uncertain native toggle, a recovered visible observation must restore native ownership"
        )

        var existingNative = SpotlightHandoffState()
        let reused = existingNative.begin()!
        precondition(existingNative.requestNative(generation: reused))
        precondition(
            !existingNative.claimNativeInvocation(isVisible: true, generation: reused),
            "If native ignored the preceding close, reopening must reuse it rather than toggle it closed"
        )
        precondition(
            existingNative.claimNativeInvocation(isVisible: false, generation: reused),
            "A native opening is needed only after absence is positively observed"
        )
        precondition(
            !existingNative.claimNativeInvocation(isVisible: false, generation: reused),
            "Repeated hidden observations must never post another native toggle"
        )

        existingNative.recordNativePresence(isVisible: true, generation: reused)
        existingNative.nativeWillClose()
        _ = existingNative.begin()!
        precondition(
            existingNative.nativeMayBePresent,
            "A replacement droplet must retain the outstanding native window so cancelling it also closes native"
        )

        var slowNative = SpotlightHandoffState()
        let slowFirst = slowNative.begin()!
        precondition(slowNative.requestNative(generation: slowFirst))
        precondition(slowNative.claimNativeInvocation(isVisible: false, generation: slowFirst))
        slowNative.nativeWillClose()
        let slowReplacement = slowNative.begin()!
        precondition(slowNative.requestNative(generation: slowReplacement))
        precondition(
            !slowNative.claimNativeInvocation(isVisible: false, generation: slowReplacement),
            "A slow native opening must not receive a second toggle from a replacement droplet"
        )

        let validPreference: [String: Any] = ["enabled": true, "value": ["parameters": [32, 49, 1048576]]]
        precondition(SpotlightShortcut(preference: validPreference)?.keyCode == 49)
        precondition(SpotlightShortcut(preference: ["enabled": false]) == nil)
        precondition(
            SpotlightShortcut(preference: ["enabled": true, "value": ["parameters": [32, -1, 1048576]]]) == nil
        )
        precondition(
            SpotlightShortcut(preference: ["enabled": true, "value": ["parameters": [32, 49, 0]]]) == nil
        )

        let workerGate      = SpotlightAXOperationGate()
        let workerRevision  = workerGate.advance()
        let workerOperation = workerGate.operation(revision: workerRevision)
        precondition(workerGate.remaining(workerOperation) > 0)

        let readStarted        = DispatchSemaphore(value: 0)
        let readMayReturn      = DispatchSemaphore(value: 0)
        let inspectionFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            readStarted.signal()
            readMayReturn.wait()
            precondition(
                workerGate.remaining(workerOperation) == 0,
                "A delayed AX read must not regain permission to move after cancellation"
            )
            inspectionFinished.signal()
        }

        precondition(readStarted.wait(timeout: .now() + 1) == .success)
        let freshRevision = workerGate.advance()
        readMayReturn.signal()
        precondition(inspectionFinished.wait(timeout: .now() + 1) == .success)
        precondition(workerGate.remaining(workerGate.operation(revision: freshRevision)) > 0)
        precondition(
            workerGate.remaining(workerGate.operation(revision: freshRevision, budget: 0)) == 0,
            "The entire inspection must stop at its deadline"
        )

        // The key tap calls its C callback on its own thread. It must run
        // there without a main-actor assertion; it once trapped on the first
        // key. An idle gate lets the key through without touching the main actor.
        let tap = SpotlightKeyTap()
        let key = CGEvent(
            keyboardEventSource: nil,
            virtualKey         : 0,
            keyDown            : true
        )!
        nonisolated(unsafe) let offMainKey = key
        let context = Unmanaged.passUnretained(tap).toOpaque()
        nonisolated(unsafe) let offMainContext = context
        let callbackFinished = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var passedThrough = false
        let tapThread = Thread {
            passedThrough = SpotlightKeyTap.callback(
                OpaquePointer(bitPattern: 1)!,
                .keyDown,
                offMainKey,
                offMainContext
            ) != nil
            callbackFinished.signal()
        }

        tapThread.start()
        callbackFinished.wait()
        precondition(passedThrough, "Ordinary typing passes the tap thread untouched")
        withExtendedLifetime(tap) {}

        print("Spotlight handoff, shortcut, AX cancellation, and key tap checks passed")
    }
}

#endif
