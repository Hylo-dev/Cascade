//
//  PluginManifest.swift
//  CascadeKit
//

import Foundation

/// PluginManifest is manifest v2, the only version Cascade decodes: what a plugin is and what
/// each of its features needs. Execution mode and trust are absent on purpose: the host takes
/// them from the package signature.
public struct PluginManifest: Codable, Equatable, Sendable {

    public static let maximumBytes = 65_536

    public let manifestVersion: Int
    public let id             : PluginID
    public let version        : String
    public let compatibility  : PluginCompatibility
    public let execution      : PluginExecution
    public let sourceApp      : String?
    public let requires       : [PluginRequirement]
    public let features       : [PluginFeature]
    public let resources      : PluginResources

    public init(
        manifestVersion: Int,
        id             : PluginID,
        version        : String,
        compatibility  : PluginCompatibility,
        execution      : PluginExecution,
        sourceApp      : String?,
        requires       : [PluginRequirement],
        features       : [PluginFeature],
        resources      : PluginResources
    ) throws {
        self.manifestVersion = manifestVersion
        self.id              = id
        self.version         = version
        self.compatibility   = compatibility
        self.execution       = execution
        self.sourceApp       = sourceApp
        self.requires        = requires
        self.features        = features
        self.resources       = resources

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container   = try decoder.container(keyedBy: CodingKeys.self)
        manifestVersion = try container.decode(Int.self, forKey: .manifestVersion)
        id              = try container.decode(PluginID.self, forKey: .id)
        version         = try container.decode(String.self, forKey: .version)
        compatibility   = try container.decode(PluginCompatibility.self, forKey: .compatibility)
        execution       = try container.decode(PluginExecution.self, forKey: .execution)
        sourceApp       = try container.decodeIfPresent(String.self, forKey: .sourceApp)
        requires        = try container.decodeIfPresent([PluginRequirement].self, forKey: .requires) ?? []
        features        = try container.decode([PluginFeature].self, forKey: .features)
        resources       = try container.decode(PluginResources.self, forKey: .resources)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(manifestVersion == 2, "Unsupported manifest version")
        try ContractValidation.require(ContractValidation.semver(version), "Invalid plugin SemVer")
        try ContractValidation.require(sourceApp.map { PluginID(rawValue: $0) != nil } ?? true, "Invalid source app")

        try ContractValidation.require(requires.count <= 32, "Too many requirements")
        for requirement in requires {
            try requirement.validate()
        }

        try ContractValidation.require((1...16).contains(features.count), "A plugin declares one to sixteen features")
        try ContractValidation.unique(features.map(\.id), "Duplicate features")
        try ContractValidation.bytes(self, maximum: Self.maximumBytes)
    }

    /// decode rejects oversized data before the JSON parser sees it.
    public static func decode(_ data: Data) throws -> PluginManifest {
        try ContractValidation.require(data.count <= maximumBytes, "Manifest exceeds 64 KiB")

        return try JSONDecoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case manifestVersion
        case id
        case version
        case compatibility
        case execution
        case sourceApp
        case requires = "REQUIRES"
        case features
        case resources
    }
}
