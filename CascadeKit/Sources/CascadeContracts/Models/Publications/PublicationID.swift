//
//  PublicationID.swift
//  CascadeKit
//

import Foundation

/// PublicationID identifies one host-assigned publication, independently of process lifetime.
public struct PublicationID: Codable, Hashable, Sendable {
    public let addonID: AddonID
    public let instanceID: UUID
    public let sessionID: UUID
    public init(addonID: AddonID, instanceID: UUID, sessionID: UUID) {
        self.addonID = addonID
        self.instanceID = instanceID
        self.sessionID = sessionID
    }
    /// validateOwner compares claims with the peer namespace supplied by the authenticated host.
    public func validateOwner(_ authenticatedAddonID: AddonID) throws {
        try ContractValidation.require(
            addonID == authenticatedAddonID,
            "Publication owner does not match authenticated peer"
        )
    }
}
