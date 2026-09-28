//
//  NotchActivityLifetime.swift
//  CascadeKit
//

import Foundation

/// NotchActivityLifetime is a finite session with an optional earlier freshness
/// deadline. Cascade adopts the HIG's recommended eight-hour duration as its
/// cap, independently of ActivityKit. End the activity earlier whenever the
/// actual task ends.
public nonisolated struct NotchActivityLifetime: Sendable, Equatable {
    public static let maximumDuration: TimeInterval = 8 * 60 * 60
    public let startedAt: Date
    public let expiresAt: Date
    public let staleDate: Date?

    public init(
        startedAt: Date = .now,
        duration: TimeInterval = maximumDuration,
        staleDate: Date? = nil
    ) {
        let start = startedAt.timeIntervalSince1970.isFinite ? startedAt : .now
        let duration = duration.isFinite ? min(Self.maximumDuration, max(0, duration)) : 0
        let end = start.addingTimeInterval(duration)
        self.startedAt = start
        self.expiresAt = end
        self.staleDate = staleDate.flatMap { date in
            date.timeIntervalSince1970.isFinite ? min(end, max(start, date)) : nil
        }
    }

    public func isStale(at date: Date) -> Bool {
        staleDate.map { date >= $0 } ?? false
    }

    public func hasEnded(at date: Date) -> Bool { date >= expiresAt }
}
