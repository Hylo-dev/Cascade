//
//  SpotlightShortcut.swift
//  Cascade
//

import CoreGraphics

/// SpotlightShortcut reads the user's enabled system shortcut without changing
/// it. Invalid or modifier-free bindings disable interception instead of taking
/// an ordinary typing key away from the foreground app.
nonisolated struct SpotlightShortcut {

    let keyCode: CGKeyCode
    let flags  : CGEventFlags

    init?(preference: [String: Any]) {
        guard preference["enabled"] as? Bool == true,
              let value      = preference["value"] as? [String: Any],
              let parameters = value["parameters"] as? [Int],
              parameters.count == 3,
              parameters[1] >= 0,
              parameters[1] <= 127,
              parameters[2] > 0
        else { return nil }

        let flags = CGEventFlags(rawValue: UInt64(parameters[2]))
            .intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift])
        guard !flags.isEmpty else { return nil }

        keyCode    = CGKeyCode(parameters[1])
        self.flags = flags
    }

    func matches(_ event: CGEvent) -> Bool {
        event.getIntegerValueField(.keyboardEventKeycode) == Int64(keyCode)
            && event.flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]) == flags
    }
}
