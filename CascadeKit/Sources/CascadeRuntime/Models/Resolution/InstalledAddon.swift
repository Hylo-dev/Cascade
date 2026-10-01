//
//  InstalledAddon.swift
//  CascadeKit
//

import CascadeContracts

public struct InstalledAddon: Equatable, Sendable {

    public let manifest        : AddonManifest
    public let verifiedIdentity: VerifiedAddonIdentity
    public let digest          : String
    public let enabled         : Bool

    public init(
        manifest        : AddonManifest,
        verifiedIdentity: VerifiedAddonIdentity,
        digest          : String,
        enabled         : Bool
    ) throws {
        guard verifiedIdentity.addonID == manifest.id,
              !verifiedIdentity.publisher.isEmpty,
              !digest.isEmpty,
              digest.utf8.count <= 512
        else {
            throw AddonFailure(
                code  : .invalidPayload,
                reason: "The verified identity or artifact digest does not match the addon manifest."
            )
        }

        self.manifest         = manifest
        self.verifiedIdentity = verifiedIdentity
        self.digest           = digest
        self.enabled          = enabled
    }
}
