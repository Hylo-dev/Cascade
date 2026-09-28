//
//  ResolutionPolicy.swift
//  CascadeKit
//

import Foundation
import CascadeContracts

public struct ResolutionPolicy: Hashable, Sendable {
    public let maximumAddons: Int
    public let maximumEdges: Int
    public let maximumDepth: Int
    public let maximumAlternativeSteps: Int
    public init(maximumAddons: Int = 32, maximumEdges: Int = 128, maximumDepth: Int = 8, maximumAlternativeSteps: Int = 256) {
        // Callers may tighten host limits, but cannot raise the v1 ceilings.
        self.maximumAddons = max(1, min(maximumAddons, 32))
        self.maximumEdges = max(0, min(maximumEdges, 128))
        self.maximumDepth = max(0, min(maximumDepth, 8))
        self.maximumAlternativeSteps = max(0, min(maximumAlternativeSteps, 256))
    }
}
