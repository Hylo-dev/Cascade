//
//  CascadeText.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// CascadeText builds a validated durable text description.
public struct CascadeText: CascadeContent {
    public let contentNode: ContentNode

    public init(_ text: String) throws {
        contentNode = try .text(text)
    }
}
