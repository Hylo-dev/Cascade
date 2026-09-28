//
//  NotchContextualPageContext.swift
//  CascadeKit
//

import CoreGraphics
import SwiftUI

public nonisolated struct NotchContextualPageContext: Sendable {
    public let availableSize: CGSize
    /// Physical camera/sensor area in SwiftUI page coordinates (top-left origin).
    /// Content may use the top shoulders while keeping this center clear.
    public let centerObstructionFrame: CGRect

    public init(
        availableSize: CGSize,
        centerObstructionFrame: CGRect = .zero
    ) {
        self.availableSize = availableSize
        self.centerObstructionFrame = centerObstructionFrame
    }
}
