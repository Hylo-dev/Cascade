//
//  ServiceAccessGrant.swift
//  CascadeKit
//

import Foundation
import CascadeContracts

public struct ServiceAccessGrant: Hashable, Codable, Sendable {
    public let consumer: AddonID
    public let requirementID: String
    public let providerIdentity: VerifiedAddonIdentity
    public init(consumer: AddonID, requirementID: String, providerIdentity: VerifiedAddonIdentity) { self.consumer = consumer; self.requirementID = requirementID; self.providerIdentity = providerIdentity }
}
