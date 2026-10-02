//
//  WidgetControl.swift
//  CascadeKit
//

/// WidgetControl is a button a first-party widget offers. The timer and the stopwatch share the
/// ones they both have, so a start or a reset looks, reads and acts the same in either. Each
/// sends the action its manifest declares and the kernel sends back when it is pressed; resume
/// is start as a paused widget names it, so it sends `start`, which resumes whatever is paused,
/// and is never read back.
enum WidgetControl: Sendable {

    case addOneMinute
    case addFiveMinutes
    case start
    case resume
    case pause
    case reset

    init?(action: String) {
        switch action {
            case "add1" : self = .addOneMinute
            case "add5" : self = .addFiveMinutes
            case "start": self = .start
            case "pause": self = .pause
            case "reset": self = .reset
            default     : return nil
        }
    }

    var action: String {
        switch self {
            case .addOneMinute  : "add1"
            case .addFiveMinutes: "add5"
            case .start, .resume: "start"
            case .pause         : "pause"
            case .reset         : "reset"
        }
    }
}
