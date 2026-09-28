//
//  AddonManifest.swift
//  CascadeKit
//

import Foundation

/// AddonManifest is a validated value in the version 1 addon protocol.
public struct AddonManifest: Codable, Equatable, Sendable {
    public let manifestVersion: Int
    public let id: AddonID
    public let version: String
    public let compatibility: AddonCompatibility
    public let execution: AddonExecution
    public let sourceApp: SourceApplication?
    public let bundledLibraries: [BundledLibrary]
    public let requires: [AddonRequirement]
    public let provides: [ProvidedService]
    public let features: [AddonFeature]
    public let permissions: [AddonPermission]
    public let resources: AddonResourceRequest

    public init(
        manifestVersion: Int,
        id: AddonID,
        version: String,
        compatibility: AddonCompatibility,
        execution: AddonExecution,
        sourceApp: SourceApplication?,
        bundledLibraries: [BundledLibrary],
        requires: [AddonRequirement],
        provides: [ProvidedService],
        features: [AddonFeature],
        permissions: [AddonPermission],
        resources: AddonResourceRequest
    ) throws {
        self.manifestVersion = manifestVersion
        self.id = id
        self.version = version
        self.compatibility = compatibility
        self.execution = execution
        self.sourceApp = sourceApp
        self.bundledLibraries = bundledLibraries
        self.requires = requires
        self.provides = provides
        self.features = features
        self.permissions = permissions
        self.resources = resources
        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )
        let container = try decoder.container(keyedBy: CodingKeys.self)
        manifestVersion = try container.decode(Int.self, forKey: .manifestVersion)
        id = try container.decode(AddonID.self, forKey: .id)
        version = try container.decode(String.self, forKey: .version)
        compatibility = try container.decode(AddonCompatibility.self, forKey: .compatibility)
        execution = try container.decode(AddonExecution.self, forKey: .execution)
        sourceApp = try container.decodeIfPresent(SourceApplication.self, forKey: .sourceApp)
        bundledLibraries = try container.decode([BundledLibrary].self, forKey: .bundledLibraries)
        requires = try container.decode([AddonRequirement].self, forKey: .requires)
        provides = try container.decode([ProvidedService].self, forKey: .provides)
        features = try container.decode([AddonFeature].self, forKey: .features)
        permissions = try container.decode([AddonPermission].self, forKey: .permissions)
        resources = try container.decode(AddonResourceRequest.self, forKey: .resources)
        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(manifestVersion == 1, "Unsupported manifest major")
        try ContractValidation.require(ContractValidation.semver(version), "Invalid package SemVer")
        try ContractValidation.require(requires.count <= 32, "Too many requirements")
        try ContractValidation.unique(features.map(\.id), "Duplicate features")
        try ContractValidation.unique(provides.map(\.id), "Duplicate services")
        try ContractValidation.unique(bundledLibraries.map(\.name), "Duplicate libraries")
        try ContractValidation.unique(permissions.map { $0.id.rawValue }, "Duplicate permissions")
        try ContractValidation.bytes(self, maximum: 65_536)
    }
    /// decode rejects oversized transport data before invoking the JSON parser.
    public static func decode(_ data: Data) throws -> AddonManifest {
        try ContractValidation.require(data.count <= 65_536, "Manifest exceeds 64 KiB")
        return try JSONDecoder().decode(Self.self, from: data)
    }
    private enum CodingKeys: String, CodingKey, CaseIterable {
        case manifestVersion
        case id
        case version
        case compatibility
        case execution
        case sourceApp
        case bundledLibraries
        case requires = "REQUIRES"
        case provides = "PROVIDES"
        case features
        case permissions
        case resources
    }
}
