//
//  CascadeRow.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// CascadeRow builds a validated durable row description.
public struct CascadeRow: CascadeContent {
    public let contentNode: ContentNode

    public init(@CascadeContentBuilder content: () throws -> [ContentNode]) throws {
        contentNode = try .row(content())
    }
}
