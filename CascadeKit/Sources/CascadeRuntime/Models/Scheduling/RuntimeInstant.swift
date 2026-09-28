//
//  RuntimeInstant.swift
//  CascadeKit
//

import Foundation

/// RuntimeInstant pairs civil time with elapsed time in this runtime incarnation.
/// It is deliberately not Codable: persisted dates need fresh monotonic deadlines.
public struct RuntimeInstant: Equatable, Sendable {
    public let wall: Date
    public let monotonic: Duration

    public init(wall: Date, monotonic: Duration) {
        self.wall = wall
        self.monotonic = monotonic
    }
}
