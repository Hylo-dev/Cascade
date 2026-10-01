//
//  BlockedFeature.swift
//  CascadeKit
//

import CascadeContracts

public struct BlockedFeature: Equatable, Sendable {

    public let addonID  : AddonID
    public let featureID: String
    public let failure  : AddonFailure
}
