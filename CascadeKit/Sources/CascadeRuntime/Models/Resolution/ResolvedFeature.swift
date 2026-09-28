//
//  ResolvedFeature.swift
//  CascadeKit
//

import Foundation
import CascadeContracts

public struct ResolvedFeature: Hashable, Codable, Sendable {
    public let addonID: AddonID
    public let featureID: String
}
