//
//  CaffeinateCommand.swift
//  Cascade
//

import CascadeContracts

/// CaffeinateCommand is one thing the user can ask of the keep-awake session. The widget's
/// controls produce all of them but `toggle`, which only the global shortcut sends. Start and
/// stop are absolute and idempotent: the power control carries whichever of the two matches the
/// state it shows, so a late or repeated one cannot flip the session the wrong way.
nonisolated enum CaffeinateCommand: Equatable, Sendable {

    case start
    case stop
    case toggle
    case extend
    case stepUp
    case stepDown
    case setKeepsDisplayAwake(Bool)
    case setGlyph(CaffeinateGlyph)

    /// isPreference tells a command that only changes what the next session looks like from one
    /// that acts on the session. A preference may run while the plugin holds no lease.
    var isPreference: Bool {
        switch self {
            case .setKeepsDisplayAwake, .setGlyph: true
            default                              : false
        }
    }

    static let plugin = PluginID(rawValue: "com.cascade.caffeinate")!

    /// init?(_:) reads the action the broker accepted, by its manifest name, and fails for an
    /// action that is not a command on the session, such as `caffeinate.options`, or for a
    /// display toggle that carries no boolean.
    init?(_ event: PluginActionEvent) {
        switch event.action {
            case "caffeinate.start"        : self = .start
            case "caffeinate.stop"         : self = .stop
            case "caffeinate.extend"       : self = .extend
            case "caffeinate.duration.up"  : self = .stepUp
            case "caffeinate.duration.down": self = .stepDown

            case "caffeinate.display":
                guard case .bool(let keepsDisplayAwake)? = event.value else { return nil }

                self = .setKeepsDisplayAwake(keepsDisplayAwake)

            default:
                return nil
        }
    }
}
