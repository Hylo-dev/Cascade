//
//  PluginDocument.swift
//  CascadeKit
//

import Foundation

/// PluginDocument is one publication's content: the schema it was written in, a root node and
/// the glass lights, which stay a document-level feature. It is validated before the kernel
/// keeps it, and a document that breaks a limit is rejected whole, so the previous one stays.
public struct PluginDocument: Codable, Equatable, Sendable {

    public static let schemaVersion    = 2
    public static let maximumBytes     = 65_536
    public static let maximumNodes     = 256
    public static let maximumDepth     = 12
    public static let maximumModifiers = 16

    public let schema     : Int
    public let root       : PluginNode
    public let glassLights: [GlassLight]

    public init(
        root       : PluginNode,
        glassLights: [GlassLight] = [],
        schema     : Int = PluginDocument.schemaVersion
    ) throws {
        self.schema      = schema
        self.root        = root
        self.glassLights = glassLights

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema        = try container.decode(Int.self, forKey: .schema)
        root          = try container.decode(PluginNode.self, forKey: .root)
        glassLights   = try container.decodeIfPresent([GlassLight].self, forKey: .glassLights) ?? []

        try validateStructure()
    }

    /// decode rejects oversized data before the JSON parser sees it.
    public static func decode(_ data: Data) throws -> PluginDocument {
        try ContractValidation.require(data.count <= maximumBytes, "Document exceeds 64 KiB")

        return try JSONDecoder().decode(Self.self, from: data)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case schema
        case root
        case glassLights
    }
}
