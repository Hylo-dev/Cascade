//
//  DeadlineQueue.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// DeadlineQueue owns the host's pending wakeups without installing any timers.
/// The runtime rearms one wakeup from nextDelay and reevaluates it after a civil
/// clock change or system wake. Wall dates and elapsed deadlines never overwrite
/// one another. Expired entries are removed once, with no catch-up tick generation.
public struct DeadlineQueue: Sendable {

    public enum Deadline: Equatable, Sendable {

        case wall     (Date)
        case monotonic(Duration)
    }

    public struct Entry: Equatable, Sendable {

        public let id      : UUID
        public let owner   : AddonID
        public let deadline: Deadline
    }

    private static let entryCharge = 1_024

    private let maximumEntries: Int
    private var entries       : [UUID: Entry] = [:]

    public var retainedBytes: Int { entries.count * Self.entryCharge }
    public var count        : Int { entries.count }

    public init(maximumEntries: Int = 1_024) {
        self.maximumEntries = min(1_024, max(0, maximumEntries))
    }

    /// schedule replaces a host key in place, including an earlier pending date.
    /// IDs are scoped to their authenticated owner; replacement never grows storage.
    public mutating func schedule(
        _ id    : UUID,
        owner   : AddonID,
        deadline: Deadline
    ) throws {
        switch deadline {
            case .wall(let date):
                guard date.timeIntervalSince1970.isFinite else {
                    throw AddonFailure(
                        code  : .invalidPayload,
                        reason: "A deadline must be a finite date."
                    )
                }

            case .monotonic(let duration):
                guard duration >= .zero else {
                    throw AddonFailure(
                        code  : .invalidPayload,
                        reason: "An elapsed deadline cannot be negative."
                    )
                }
        }

        if let existing = entries[id] {
            guard existing.owner == owner else {
                throw AddonFailure(
                    code  : .permissionDenied,
                    reason: "The deadline belongs to another addon."
                )
            }
        } else if entries.count >= maximumEntries {
            throw AddonFailure(
                code  : .resourceDenied,
                reason: "The host deadline queue is full."
            )
        }

        entries[id] = Entry(
            id      : id,
            owner   : owner,
            deadline: deadline
        )
    }

    public mutating func cancel(
        _ id : UUID,
        owner: AddonID
    ) throws {
        guard let existing = entries[id] else { return }
        guard existing.owner == owner else {
            throw AddonFailure(
                code  : .permissionDenied,
                reason: "The deadline belongs to another addon."
            )
        }

        entries.removeValue(forKey: id)
    }

    public mutating func remove(owner: AddonID) {
        for id in entries.keys.filter({ entries[$0]?.owner == owner }) {
            entries.removeValue(forKey: id)
        }
    }

    /// nextDelay scans at most 1,024 entries only after host events, without making
    /// a temporary array. Constant-time replacement avoids accumulating cancelled
    /// heap entries; this bounded scan also handles wall-clock jumps directly.
    public func nextDelay(at instant: RuntimeInstant) throws -> Duration? {
        try validate(instant)

        var earliest: Duration?
        for entry in entries.values {
            let delay = remaining(entry.deadline, at: instant)
            earliest  = earliest.map { min($0, delay) } ?? delay
        }

        return earliest
    }

    /// drainDue returns each due entry once. Ordering across the two independent
    /// clock domains is intentionally unspecified; job priority belongs to scheduler.
    public mutating func drainDue(at instant: RuntimeInstant) throws -> [Entry] {
        try validate(instant)

        let due = entries.values.filter { remaining($0.deadline, at: instant) == .zero }
        for entry in due { entries.removeValue(forKey: entry.id) }
        return due
    }

    private func validate(_ instant: RuntimeInstant) throws {
        guard instant.wall.timeIntervalSince1970.isFinite, instant.monotonic >= .zero else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "The runtime clock is invalid."
            )
        }
    }

    private func remaining(
        _ deadline: Deadline,
        at instant: RuntimeInstant
    ) -> Duration {
        switch deadline {
            case .wall(let date):
                // Distant, but finite, protocol dates can overflow a Double subtraction
                // or Duration conversion. Cap the sleep, not the stored absolute date.
                let seconds = min(1_000_000_000_000, max(0, date.timeIntervalSince(instant.wall)))
                return .seconds(seconds)

            case .monotonic(let deadline):
                return max(.zero, deadline - instant.monotonic)
        }
    }
}
