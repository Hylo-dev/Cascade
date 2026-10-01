//
//  CascadeCountdown.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// CascadeCountdown builds a validated durable countdown description.
public struct CascadeCountdown: CascadeContent {

    public let contentNode: ContentNode

    public init(until: Date) throws {
        contentNode = try .countdown(until: until)
    }
}
