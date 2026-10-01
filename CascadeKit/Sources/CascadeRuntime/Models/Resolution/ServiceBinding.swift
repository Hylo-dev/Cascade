//
//  ServiceBinding.swift
//  CascadeKit
//

import CascadeContracts

public struct ServiceBinding: Hashable, Codable, Sendable {

    public let requirementID   : String
    public let consumer        : AddonID
    public let provider        : AddonID
    public let providerIdentity: VerifiedAddonIdentity
    public let contractVersion : SemanticVersion
    public let digest          : String
    public let featureID       : String?

    public init(
        requirementID   : String,
        consumer        : AddonID,
        provider        : AddonID,
        providerIdentity: VerifiedAddonIdentity,
        contractVersion : SemanticVersion,
        digest          : String,
        featureID       : String? = nil
    ) {
        self.requirementID    = requirementID
        self.consumer         = consumer
        self.provider         = provider
        self.providerIdentity = providerIdentity
        self.contractVersion  = contractVersion
        self.digest           = digest
        self.featureID        = featureID
    }
}
