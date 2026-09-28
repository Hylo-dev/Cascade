//
//  CascadeColumn.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// CascadeColumn builds a validated durable column description.
public struct CascadeColumn: CascadeContent {
    public let contentNode: ContentNode

    public init(@CascadeContentBuilder content: () throws -> [ContentNode]) throws {
        contentNode = try .column(content())
    }
}
