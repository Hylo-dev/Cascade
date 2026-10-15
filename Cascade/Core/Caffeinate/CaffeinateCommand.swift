//
//  CaffeinateCommand.swift
//  Cascade
//

import CascadeContracts
import CascadePluginEngine
import Foundation

/// CaffeinateCommand is one thing the user can ask of the keep-awake session. The widget's
/// controls produce all of them but `toggle`, which only the global shortcut sends. Start and
/// stop are absolute and idempotent: the power control carries whichever of the two matches the
/// state it shows, so a late or repeated one cannot flip the session the wrong way.
nonisolated enum CaffeinateCommand: Equatable, Sendable {

    case start
    case stop
    case toggle

    /// setMode picks how the next session, or the running one, ends: never, after the last
    /// duration, or at the last end time. setDuration and setUntil are the ruler's absolute
    /// values: minutes, and an instant. All three are target commands.
    case setMode(CaffeinateTargetKind)
    case setDuration(minutes: Int)
    case setUntil(Date)

    case setKeepsDisplayAwake(Bool)
    case setGlyph(CaffeinateGlyph)

    /// isPreference tells a command that only changes what the next session looks like from one
    /// that acts on the session. A preference may run while sessions are not allowed.
    var isPreference: Bool {
        switch self {
            case .setKeepsDisplayAwake, .setGlyph: true
            default                              : false
        }
    }

    /// isTargetChange marks the commands that choose how a session ends. They are preferences
    /// while no session runs, setting what the next one will do, and session commands while one
    /// does, moving its end. The service therefore lets them through the session gate only when
    /// no session is running; see `CaffeinateService.perform`.
    var isTargetChange: Bool {
        switch self {
            case .setMode, .setDuration, .setUntil: true
            default                               : false
        }
    }

    static let plugin = PluginID(rawValue: "com.cascade.caffeinate")!

    /// sessionsAllowed reads the engine's plugin states as the service's permission: a session
    /// may run while Caffeinate is active, and not while it is switched off, quarantined, disabled
    /// after a hang or not registered yet. PluginHost's own state does not enter: the assertion
    /// needs no PluginHost, and the kernel keeps drawing the last publication while it is away.
    static func sessionsAllowed(in plugins: [PluginID: PluginState]) -> Bool {
        plugins[plugin] == .active
    }

    /// init?(_:) reads the action the broker accepted, by its manifest name, and fails for an
    /// action that is not a command on the session, such as `caffeinate.options`, or for a
    /// display toggle that carries no boolean.
    init?(_ event: PluginActionEvent) {
        switch event.action {
            case "caffeinate.start"        : self = .start
            case "caffeinate.stop"         : self = .stop

            case "caffeinate.mode.indefinite": self = .setMode(.indefinite)
            case "caffeinate.mode.duration"  : self = .setMode(.duration)
            case "caffeinate.mode.until"     : self = .setMode(.until)

            case "caffeinate.duration.set":
                guard case .number(let minutes)? = event.value,
                      minutes.isFinite,
                      minutes == minutes.rounded(),
                      abs(minutes) < 1e9
                else { return nil }

                self = .setDuration(minutes: Int(minutes))

            case "caffeinate.until.set":
                guard case .number(let seconds)? = event.value,
                      seconds.isFinite,
                      abs(seconds) <= 253_402_300_799
                else { return nil }

                self = .setUntil(Date(timeIntervalSince1970: seconds))

            case "caffeinate.display":
                guard case .bool(let keepsDisplayAwake)? = event.value else { return nil }

                self = .setKeepsDisplayAwake(keepsDisplayAwake)

            default:
                return nil
        }
    }
}
