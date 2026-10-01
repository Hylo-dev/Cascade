//
//  ContentDocument.swift
//  CascadeKit
//

import Foundation

/// ContentDocument is a validated, versioned description of addon content.
public struct ContentDocument: Codable, Equatable, Sendable {

    public let schemaVersion     : Int
    public let root              : ContentNode
    public let accessibilityLabel: String
    public let privacy           : Privacy
    public let assets            : [String]
    public let glassLights       : [GlassLight]?

    public var assetIDs: [String] { assets }

    public init(
        schemaVersion     : Int,
        root              : ContentNode,
        accessibilityLabel: String,
        privacy           : Privacy,
        assets            : [String],
        glassLights       : [GlassLight]? = nil
    ) throws {
        self.schemaVersion      = schemaVersion
        self.root               = root
        self.accessibilityLabel = accessibilityLabel
        self.privacy            = privacy
        self.assets             = assets
        self.glassLights        = glassLights

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container      = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion      = try container.decode(Int.self, forKey: .schemaVersion)
        root               = try container.decode(ContentNode.self, forKey: .root)
        accessibilityLabel = try container.decode(String.self, forKey: .accessibilityLabel)
        privacy            = try container.decode(Privacy.self, forKey: .privacy)
        assets             = try BoundedContractArray.decode(
            String.self,
            from   : container.superDecoder(forKey: .assets),
            maximum: 64
        )
        try ContractValidation.require(
            !container.contains(.glassLights) || schemaVersion >= 2,
            "Glass lights require content schema 2 or later"
        )

        if container.contains(.glassLights), try !container.decodeNil(forKey: .glassLights) {
            glassLights = try BoundedContractArray.decode(
                GlassLight.self,
                from   : container.superDecoder(forKey: .glassLights),
                maximum: GlassLight.maximumCount
            )
        } else {
            glassLights = nil
        }

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require((1...3).contains(schemaVersion), "Unsupported content schema")
        try ContractValidation.require(
            glassLights == nil || schemaVersion >= 2,
            "Glass lights require content schema 2 or later"
        )
        try ContractValidation.require(
            schemaVersion == 3 || !root.containsFileWorkspace,
            "File workspace requires content schema 3"
        )
        try ContractValidation.require(
            (glassLights?.count ?? 0) <= GlassLight.maximumCount,
            "Too many glass lights"
        )
        try ContractValidation.require(
            !accessibilityLabel.isEmpty && accessibilityLabel.utf8.count <= 4096,
            "Invalid accessibility label"
        )
        try ContractValidation.unique(assets, "Invalid asset list")
        try ContractValidation.require(
            assets.allSatisfy(ContractValidation.identifier)
                && root.referencedAssets.isSubset(of: Set(assets)),
            "Undeclared asset reference"
        )
        try ContractValidation.unique(root.actionIdentifiers, "Duplicate actions")
        try ContractValidation.bytes(self, maximum: 65_536)
    }

    public enum Privacy: String, Codable, Sendable {

        case publicContent, sensitive

        public static var `public`: Self { .publicContent }

        public init(from decoder: any Decoder) throws {
            let value = try decoder.singleValueContainer().decode(String.self)
            switch value {
                case "public", "publicContent": self = .publicContent
                case "sensitive"              : self = .sensitive
                default: throw AddonFailure(code: .invalidPayload, reason: "Unknown privacy")
            }
        }
    }

    /// encode validates and archives bounded values without retaining provider objects.
    public func encode() throws -> Data {
        try validate()

        return try JSONEncoder().encode(self)
    }

    /// decode checks the raw budget before JSON parsing begins.
    public static func decode(_ data: Data) throws -> Self {
        try ContractValidation.require(data.count <= 65_536, "Content exceeds 64 KiB")

        return try JSONDecoder().decode(Self.self, from: data)
    }

    public init(
        schemaVersion     : Int = 1,
        root              : ContentNode,
        privacy           : Privacy,
        accessibilityLabel: String,
        assetIDs          : [String] = [],
        glassLights       : [GlassLight]? = nil
    ) throws {
        try self.init(
            schemaVersion     : schemaVersion,
            root              : root,
            accessibilityLabel: accessibilityLabel,
            privacy           : privacy,
            assets            : assetIDs,
            glassLights       : glassLights
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case schemaVersion
        case root
        case accessibilityLabel
        case privacy
        case assets
        case glassLights
    }
}
