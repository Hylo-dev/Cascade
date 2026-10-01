//
//  CascadeClock.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// CascadeClock builds a validated durable clock description.
public struct CascadeClock: CascadeContent {

    public let contentNode: ContentNode

    public init(format: ClockFormat = .hourMinute) throws {
        contentNode = try .clock(format: format)
    }
}
