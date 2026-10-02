//
//  DurationText.swift
//  CascadeKit
//

import Foundation

/// durationText is a span of time as the kernel's running timer text shows one, so a timer or a
/// stopwatch that stops reads the same as while it ran: minutes and seconds, "1:15", with the
/// hours before them past an hour, "1:02:05". It counts whole seconds and drops a part of one,
/// as a stopwatch does; a countdown, which shows a second that has begun as a whole one, rounds
/// up before it asks.
func durationText(_ seconds: TimeInterval) -> String {
    let whole   = Int(max(0, seconds).rounded(.down))
    let hours   = whole / 3_600
    let minutes = whole / 60 % 60
    let rest    = whole % 60

    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, rest)
        : String(format: "%d:%02d", minutes, rest)
}
