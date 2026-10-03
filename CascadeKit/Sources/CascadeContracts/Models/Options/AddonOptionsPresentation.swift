//
//  AddonOptionsPresentation.swift
//  CascadeKit
//

import Foundation

/// AddonOptionsPresentation is host-approved data, not a wire request. The host must
/// recheck its exact origin after crossing to the main actor and before installing it.
public struct AddonOptionsPresentation: Sendable {

    public let request   : AddonOptionsRequest
    public let origin    : AddonOptionsOrigin
    public let generation: ConnectionGeneration
    public let expiresAt : Date

    public init(
        request   : AddonOptionsRequest,
        origin    : AddonOptionsOrigin,
        generation: ConnectionGeneration,
        expiresAt : Date
    ) {
        self.request    = request
        self.origin     = origin
        self.generation = generation
        self.expiresAt  = expiresAt
    }
}
