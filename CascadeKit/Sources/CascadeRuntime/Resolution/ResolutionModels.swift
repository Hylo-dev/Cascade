//
//  ResolutionModels.swift
//  CascadeKit
//

import Foundation
import CascadeContracts

public struct VerifiedAddonIdentity: Hashable, Codable, Sendable {
    public let publisher: String
    public let addonID: AddonID

    public init(publisher: String, addonID: AddonID) {
        self.publisher = publisher
        self.addonID = addonID
    }
}

public struct InstalledAddon: Equatable, Sendable {
    public let manifest: AddonManifest
    public let verifiedIdentity: VerifiedAddonIdentity
    public let digest: String
    public let enabled: Bool

    public init(manifest: AddonManifest, verifiedIdentity: VerifiedAddonIdentity, digest: String, enabled: Bool) throws {
        guard verifiedIdentity.addonID == manifest.id, !verifiedIdentity.publisher.isEmpty,
              !digest.isEmpty, digest.utf8.count <= 512 else {
            throw AddonFailure(code: .invalidPayload, reason: "The verified identity or artifact digest does not match the addon manifest.")
        }
        self.manifest = manifest
        self.verifiedIdentity = verifiedIdentity
        self.digest = digest
        self.enabled = enabled
    }
}

public struct HostService: Hashable, Codable, Sendable {
    public let id: String
    public let version: SemanticVersion
    public init(id: String, version: SemanticVersion) { self.id = id; self.version = version }
}

public struct ApplicationAvailability: Hashable, Codable, Sendable {
    public let installed: Bool
    public let running: Bool
    public init(installed: Bool, running: Bool) { self.installed = installed; self.running = running }
}

public struct ServiceBinding: Hashable, Codable, Sendable {
    public let requirementID: String
    public let consumer: AddonID
    public let provider: AddonID
    public let providerIdentity: VerifiedAddonIdentity
    public let contractVersion: SemanticVersion
    public let digest: String
    public let featureID: String?

    public init(requirementID: String, consumer: AddonID, provider: AddonID, providerIdentity: VerifiedAddonIdentity, contractVersion: SemanticVersion, digest: String, featureID: String? = nil) {
        self.requirementID = requirementID; self.consumer = consumer; self.provider = provider
        self.providerIdentity = providerIdentity; self.contractVersion = contractVersion; self.digest = digest
        self.featureID = featureID
    }
}

public struct HostEnvironment: Sendable {
    public let osVersion: SemanticVersion
    public let hostCapabilities: [String: SemanticVersion]
    public let applications: [AddonID: ApplicationAvailability]
    public let grants: [AddonID: Set<String>]
    public var explicitBindings: [ServiceBinding]
    public let protocolVersion: (major: Int, minor: Int)
    public let serviceAccessGrants: Set<ServiceAccessGrant>

    public init(osVersion: SemanticVersion, hostCapabilities: [String: SemanticVersion], applications: [AddonID: ApplicationAvailability], grants: [AddonID: Set<String>], explicitBindings: [ServiceBinding], protocolVersion: (major: Int, minor: Int) = (1, 0), serviceAccessGrants: Set<ServiceAccessGrant> = []) {
        self.osVersion = osVersion; self.hostCapabilities = hostCapabilities; self.applications = applications
        self.grants = grants; self.explicitBindings = explicitBindings
        self.protocolVersion = protocolVersion
        self.serviceAccessGrants = serviceAccessGrants
    }
}

public struct ServiceAccessGrant: Hashable, Codable, Sendable {
    public let consumer: AddonID
    public let requirementID: String
    public let providerIdentity: VerifiedAddonIdentity
    public init(consumer: AddonID, requirementID: String, providerIdentity: VerifiedAddonIdentity) { self.consumer = consumer; self.requirementID = requirementID; self.providerIdentity = providerIdentity }
}

public struct ResolutionPolicy: Hashable, Sendable {
    public let maximumAddons: Int
    public let maximumEdges: Int
    public let maximumDepth: Int
    public let maximumAlternativeSteps: Int
    public init(maximumAddons: Int = 32, maximumEdges: Int = 128, maximumDepth: Int = 8, maximumAlternativeSteps: Int = 256) {
        // Callers may tighten host limits, but cannot raise the v1 ceilings.
        self.maximumAddons = max(1, min(maximumAddons, 32))
        self.maximumEdges = max(0, min(maximumEdges, 128))
        self.maximumDepth = max(0, min(maximumDepth, 8))
        self.maximumAlternativeSteps = max(0, min(maximumAlternativeSteps, 256))
    }
}

public struct ResolvedFeature: Hashable, Codable, Sendable {
    public let addonID: AddonID
    public let featureID: String
}

public struct BlockedAddon: Equatable, Sendable {
    public let addonID: AddonID
    public let failure: AddonFailure
}

public struct BlockedFeature: Equatable, Sendable {
    public let addonID: AddonID
    public let featureID: String
    public let failure: AddonFailure
}

public struct Resolution: Equatable, Sendable {
    public let acceptedAddons: [AddonID]
    public let blockedAddons: [BlockedAddon]
    public let enabledFeatures: [ResolvedFeature]
    public let blockedFeatures: [BlockedFeature]
    public let startOrder: [AddonID]
    public let bindings: [ServiceBinding]
    public let reverseDependents: [AddonID: [AddonID]]
}
