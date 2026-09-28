//
//  Resolution.swift
//  CascadeKit
//

import Foundation
import CascadeContracts

public struct Resolution: Equatable, Sendable {
    public let acceptedAddons: [AddonID]
    public let blockedAddons: [BlockedAddon]
    public let enabledFeatures: [ResolvedFeature]
    public let blockedFeatures: [BlockedFeature]
    public let startOrder: [AddonID]
    public let bindings: [ServiceBinding]
    public let reverseDependents: [AddonID: [AddonID]]
}
