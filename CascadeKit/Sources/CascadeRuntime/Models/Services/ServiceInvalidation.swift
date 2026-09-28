//
//  ServiceInvalidation.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import OSLog

public struct ServiceInvalidation: Sendable {
    public let affectedFeatures: Set<ResolvedFeature>
    public let decisions: [ServiceDecision]
}
