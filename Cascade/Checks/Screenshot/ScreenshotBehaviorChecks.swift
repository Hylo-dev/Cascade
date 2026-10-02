//
//  ScreenshotBehaviorChecks.swift
//  Cascade
//

#if SCREENSHOT_BEHAVIOR_TESTS
import CoreGraphics

@main
struct ScreenshotBehaviorChecks {

    static func main() {
        let modifiers: CGEventFlags = [.maskCommand, .maskShift]
        let gate = ScreenshotKeyGate()
        gate.update(shortcuts: ScreenshotShortcuts(preferences: [:]))

        check(gate, key: 53, flags: [], expected: .pass)
        gate.setCancellationEnabled(true)
        check(gate, key: 53, flags: .maskCommand, expected: .pass)
        check(gate, key: 53, flags: [], expected: .cancel)
        gate.setCancellationEnabled(false)
        check(gate, key: 53, flags: [], repeatKey: true, expected: .suppress)
        check(gate, key: 53, flags: [], type: .keyUp, expected: .suppress)
        check(gate, key: 53, flags: [], expected: .pass)

        for key: CGKeyCode in [20, 21, 23, 22] {
            check(gate, key: key, flags: modifiers, expected: .open)
            check(gate, key: key, flags: modifiers, repeatKey: true, expected: .suppress)
            check(gate, key: key, flags: [], type: .keyUp, expected: .suppress)
        }
        for key: CGKeyCode in [20, 21, 22] {
            check(gate, key: key, flags: [modifiers, .maskControl], expected: .open)
            check(gate, key: key, flags: [], type: .keyUp, expected: .suppress)
        }
        check(gate, key: 105, flags: [], expected: .open)
        check(gate, key: 105, flags: [], type: .keyUp, expected: .suppress)
        check(gate, key: 105, flags: .maskCommand, expected: .pass)
        check(gate, key: 20, flags: .maskCommand, expected: .pass)
        check(gate, key: 0, flags: [], expected: .pass)
        check(gate, key: 23, flags: [modifiers, .maskAlternate], expected: .pass)
        check(gate, key: 23, flags: modifiers, repeatKey: true, expected: .suppress)
        check(gate, key: 23, flags: [], type: .keyUp, expected: .suppress)

        let changed: [String: Any] = [
            "184": ["enabled": true, "value": ["parameters": [65535, 7, 1179648]]],
            "28" : ["enabled": false],
            "30" : ["enabled": true, "value": ["parameters": [52, -1, 1179648]]]
        ]
        gate.update(shortcuts: ScreenshotShortcuts(preferences: changed))
        check(gate, key: 23, flags: modifiers, expected: .pass)
        check(gate, key: 20, flags: modifiers, expected: .pass)
        check(gate, key: 21, flags: modifiers, expected: .pass)
        check(gate, key: 7, flags: modifiers, expected: .open)
        gate.update(shortcuts: nil)
        check(gate, key: 7, flags: [], type: .keyUp, expected: .pass)
        check(gate, key: 105, flags: [], expected: .pass)

        gate.update(shortcuts: ScreenshotShortcuts(preferences: [
            "184": ["enabled": true, "value": ["parameters": [65535, 107, 0]]],
            "28" : ["enabled": true, "value": ["parameters": [97, 0, 0]]]
        ]))
        check(gate, key: 107, flags: [], expected: .open)
        check(gate, key: 107, flags: [], type: .keyUp, expected: .suppress)
        check(gate, key: 0, flags: [], expected: .pass)
        gate.update(shortcuts: ScreenshotShortcuts(preferences: [
            "184": ["enabled": true, "value": ["parameters": [65535, 107, 8388608]]]
        ]))
        check(gate, key: 107, flags: [], expected: .pass)
        check(gate, key: 107, flags: .maskSecondaryFn, expected: .open)
        check(gate, key: 107, flags: [], type: .keyUp, expected: .suppress)
        print("PASS: screenshot shortcuts, native fallback, repeats and key releases")
    }

    private static func check(
        _ gate     : ScreenshotKeyGate,
        key        : CGKeyCode,
        flags      : CGEventFlags,
        type       : CGEventType = .keyDown,
        repeatKey  : Bool = false,
        expected   : ScreenshotKeyGate.Decision
    ) {
        guard let event = CGEvent(
            keyboardEventSource: nil,
            virtualKey         : key,
            keyDown            : type == .keyDown
        ) else { preconditionFailure("Cannot create keyboard fixture") }

        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: repeatKey ? 1 : 0)
        precondition(
            gate.consume(type: type, event: event) == expected,
            "Incorrect screenshot decision for key \(key), flags \(flags.rawValue), type \(type.rawValue)"
        )
    }
}
#endif
