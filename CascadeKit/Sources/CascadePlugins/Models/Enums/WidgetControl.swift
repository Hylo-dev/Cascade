//
//  WidgetControl.swift
//  CascadeKit
//

/// WidgetControl is a button a first-party widget offers, named by the action its manifest
/// declares and the kernel sends back when it is pressed. The timer and the stopwatch share the
/// ones they both have, so a start or a reset looks, reads and acts the same in either.
enum WidgetControl: String, Sendable {

    case addOneMinute   = "add1"
    case addFiveMinutes = "add5"
    case start          = "start"
    case pause          = "pause"
    case reset          = "reset"
}
