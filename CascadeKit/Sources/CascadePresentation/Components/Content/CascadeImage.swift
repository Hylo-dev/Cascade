//
//  CascadeImage.swift
//  CascadeKit
//

import CascadeContracts
import Foundation

/// CascadeImage builds a validated durable image description.
public struct CascadeImage: CascadeContent {

    public let contentNode: ContentNode

    public init(
        assetID           : String,
        accessibilityLabel: String
    ) throws {
        contentNode = try .image(
            assetID           : assetID,
            accessibilityLabel: accessibilityLabel
        )
    }
}
