//
//  CascadeSymbol.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// CascadeSymbol builds a validated durable symbol description.
public struct CascadeSymbol: CascadeContent {
    public let contentNode: ContentNode

    public init(_ name: String) throws {
        contentNode = try .symbol(name)
    }
}
