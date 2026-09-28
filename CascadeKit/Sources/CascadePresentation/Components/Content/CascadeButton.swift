//
//  CascadeButton.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// CascadeButton builds a validated durable button description.
public struct CascadeButton: CascadeContent {
    public let contentNode: ContentNode

    public init(_ action: ActionDescriptor) throws {
        contentNode = try .action(action)
    }
}
