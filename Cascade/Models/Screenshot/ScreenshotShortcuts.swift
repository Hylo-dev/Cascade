//
//  ScreenshotShortcuts.swift
//  Cascade
//

import CoreGraphics

/// ScreenshotShortcuts snapshots the native screenshot bindings before the tap
/// starts. Missing preferences use macOS defaults; an explicitly disabled or
/// malformed binding stays disabled, so interception never steals a typing key.
nonisolated struct ScreenshotShortcuts: Equatable, Sendable {

    private struct Binding: Equatable, Sendable {

        let keyCode: CGKeyCode
        let flags  : CGEventFlags
    }

    private let bindings: [Binding]

    init(preferences: [String: Any]) {
        let modifiers: CGEventFlags = [.maskCommand, .maskShift]
        let defaults: [(String, CGKeyCode, CGEventFlags)] = [
            ("28", 20, modifiers),
            ("29", 20, [modifiers, .maskControl]),
            ("30", 21, modifiers),
            ("31", 21, [modifiers, .maskControl]),
            ("184", 23, modifiers),
            ("181", 22, modifiers),
            ("182", 22, [modifiers, .maskControl])
        ]
        var bindings: [Binding] = []
        bindings.reserveCapacity(defaults.count + 1)
        for (identifier, keyCode, flags) in defaults {
            guard let preference = preferences[identifier] else {
                bindings.append(Binding(keyCode: keyCode, flags: flags))
                continue
            }

            guard let preference = preference as? [String: Any],
                  preference["enabled"] as? Bool == true,
                  let value      = preference["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [Int],
                  parameters.count == 3,
                  parameters[1] >= 0, parameters[1] < 128,
                  parameters[2] >= 0
            else { continue }

            let flags = CGEventFlags(rawValue: UInt64(parameters[2]))
                .intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn])
            let keyCode = CGKeyCode(parameters[1])
            let standardModifiers = flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
            guard !standardModifiers.isEmpty || Self.isFunctionKey(keyCode) else { continue }

            bindings.append(Binding(keyCode: keyCode, flags: flags))
        }

        // macOS exposes Print Screen on PC keyboards as F13. No modified F13
        // combinations are claimed: they may belong to another application.
        bindings.append(Binding(keyCode: 105, flags: []))
        self.bindings = bindings
    }

    /// matches compares the cached values only: no preference reads, event
    /// copies or allocations occur on the system keyboard callback.
    func matches(
        keyCode: CGKeyCode,
        flags  : CGEventFlags
    ) -> Bool {
        let modifierMask: CGEventFlags = [.maskCommand, .maskControl, .maskAlternate, .maskShift]

        return bindings.contains { binding in
            let mask = binding.flags.contains(.maskSecondaryFn)
                ? modifierMask.union(.maskSecondaryFn)
                : modifierMask
            return binding.keyCode == keyCode && binding.flags == flags.intersection(mask)
        }
    }

    /// isFunctionKey permits modifier-free native bindings without claiming
    /// ordinary typing. These are the platform's F1 through F20 virtual keys.
    private static func isFunctionKey(_ keyCode: CGKeyCode) -> Bool {
        switch keyCode {
            case 122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
                 103, 111, 105, 107, 113, 106, 64, 79, 80, 90:
                return true

            default:
                return false
        }
    }
}
