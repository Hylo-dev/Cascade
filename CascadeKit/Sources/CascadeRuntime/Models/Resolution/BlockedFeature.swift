//
//  BlockedFeature.swift
//  CascadeKit
//

import Foundation
import CascadeContracts

public struct BlockedFeature: Equatable, Sendable {
    public let addonID: AddonID
    public let featureID: String
    public let failure: AddonFailure
}
