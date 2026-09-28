//
//  ClockFormat.swift
//  CascadeKit
//

/// ClockFormat limits host formatting to locale-aware hours, minutes and seconds.
public enum ClockFormat: String, Codable, Equatable, Sendable {
    case hourMinute
    case hourMinuteSecond
}
