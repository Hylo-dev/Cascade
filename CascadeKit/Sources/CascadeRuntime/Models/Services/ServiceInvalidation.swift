//
//  ServiceInvalidation.swift
//  CascadeKit
//

public struct ServiceInvalidation: Sendable {

    public let affectedFeatures: Set<ResolvedFeature>
    public let decisions       : [ServiceDecision]
}
