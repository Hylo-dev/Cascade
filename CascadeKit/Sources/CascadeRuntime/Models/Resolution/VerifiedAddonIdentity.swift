//
//  VerifiedAddonIdentity.swift
//  CascadeKit
//

import CascadeContracts

public struct VerifiedAddonIdentity: Hashable, Codable, Sendable {

    public let publisher: String
    public let addonID  : AddonID

    public init(
        publisher: String,
        addonID  : AddonID
    ) {
        self.publisher = publisher
        self.addonID   = addonID
    }
}
