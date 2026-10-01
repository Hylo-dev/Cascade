//
//  PluginSourceEvent.swift
//  CascadeKit
//

import Foundation

/// PluginSourceEvent is the latest state of one catalog source, as flat typed fields: power
/// says whether it is charging and its level, volume its level and whether it is muted. It is
/// a state, never a delta, so the kernel keeps only the newest one per source, and a plugin
/// that missed a few still ends up right.
public struct PluginSourceEvent: Codable, Equatable, Sendable {

    public static let maximumFields = 32
    public static let maximumBytes  = 4_096

    public let source: String
    public let fields: [String: PluginValue]

    public init(
        source: String,
        fields: [String: PluginValue] = [:]
    ) throws {
        self.source = source
        self.fields = fields

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        source        = try container.decode(String.self, forKey: .source)
        fields        = try container.decodeIfPresent([String: PluginValue].self, forKey: .fields) ?? [:]

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(PluginCatalog.sources.contains(source), "Unknown source")
        try ContractValidation.require(fields.count <= Self.maximumFields, "Too many source fields")
        try ContractValidation.require(fields.keys.allSatisfy(ContractValidation.identifier), "Invalid source field name")
        try ContractValidation.require(
            fields.values.allSatisfy { value in
                guard case .number(let number) = value else { return true }

                return number.isFinite
            },
            "Source numbers must be finite"
        )
        try ContractValidation.bytes(self, maximum: Self.maximumBytes)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case source
        case fields
    }
}
