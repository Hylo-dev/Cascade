//
//  FocusSession.swift
//  StandaloneFocus
//

import CascadeContracts
import Foundation

public enum FocusCommand: String, Codable, Sendable, CaseIterable { case start, pause, resume, end }

/// FocusSession is a civil-clock reducer. Starting an already active session never resets its time.
public struct FocusSession: Codable, Equatable, Sendable {
    public enum Phase: String, Codable, Sendable { case idle, running, paused, completed, ended }
    public private(set) var phase: Phase = .idle
    public let duration: TimeInterval
    public private(set) var remaining: TimeInterval
    public private(set) var deadline: Date?
    public private(set) var timerID: UUID?

    public init(duration: TimeInterval = 25 * 60) throws {
        guard duration.isFinite, (1...86_400).contains(duration) else { throw FocusError.invalidConfiguration }
        self.duration = duration
        remaining = duration
    }

    public mutating func reconcile(now: Date) throws {
        try validate()
        guard now.timeIntervalSince1970.isFinite else { throw FocusError.invalidConfiguration }
        if phase == .running, let deadline, deadline <= now {
            phase = .completed
            remaining = 0
            self.deadline = nil
        }
    }

    public mutating func apply(_ command: FocusCommand, now: Date) throws {
        try reconcile(now: now)
        switch command {
        case .start:
            guard phase != .running && phase != .paused else { return }
            let end = try futureDate(now, interval: duration)
            timerID = UUID()
            phase = .running
            remaining = duration
            deadline = end
        case .pause:
            if phase == .paused { return }
            guard phase == .running, let deadline else { throw unavailable() }
            remaining = min(duration, max(0, deadline.timeIntervalSince(now)))
            self.deadline = nil
            phase = .paused
        case .resume:
            if phase == .running { return }
            guard phase == .paused, remaining > 0 else { throw unavailable() }
            deadline = try futureDate(now, interval: remaining)
            phase = .running
        case .end:
            timerID = timerID ?? UUID()
            phase = .ended
            remaining = 0
            deadline = nil
        }
    }

    func validate() throws {
        guard duration.isFinite, (1...86_400).contains(duration), remaining.isFinite,
            (0...duration).contains(remaining), deadline?.timeIntervalSince1970.isFinite ?? true
        else { throw FocusError.corruptState }
        switch phase {
        case .idle:
            guard timerID == nil, deadline == nil, remaining == duration else { throw FocusError.corruptState }
        case .running:
            guard timerID != nil, deadline != nil, remaining > 0 else { throw FocusError.corruptState }
        case .paused:
            guard timerID != nil, deadline == nil, remaining > 0 else { throw FocusError.corruptState }
        case .completed, .ended:
            guard timerID != nil, deadline == nil, remaining == 0 else { throw FocusError.corruptState }
        }
    }
}

func futureDate(_ now: Date, interval: TimeInterval) throws -> Date {
    let date = now.addingTimeInterval(interval)
    guard now.timeIntervalSince1970.isFinite, date.timeIntervalSince1970.isFinite, date > now
    else { throw FocusError.invalidConfiguration }
    return date
}
private func unavailable() -> AddonFailure {
    AddonFailure(code: .invalidPayload, reason: "Command unavailable in current phase")
}
