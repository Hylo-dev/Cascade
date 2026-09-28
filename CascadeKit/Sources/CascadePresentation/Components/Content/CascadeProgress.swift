//
//  CascadeProgress.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// CascadeProgress builds a validated durable progress description.
public struct CascadeProgress: CascadeContent {
    public let contentNode: ContentNode

    public init(value: Double) throws {
        contentNode = try .progress(value: value)
    }
}
