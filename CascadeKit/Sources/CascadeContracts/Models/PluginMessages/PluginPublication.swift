//
//  PluginPublication.swift
//  CascadeKit
//

import Foundation

/// PluginPublication is what one feature shows on one surface. A document replaces whatever the
/// feature showed there; no document withdraws it. `staleAfter` says, in seconds, how old the
/// content may grow before the kernel asks for a fresh one when the surface becomes visible
/// again. Content the kernel draws itself, such as a clock face, never goes stale, so it leaves
/// `staleAfter` out.
public struct PluginPublication: Codable, Equatable, Sendable {

    public static let maximumStaleAfter = 86_400.0

    public let feature   : String
    public let surface   : PluginSurfaceKind
    public let document  : PluginDocument?
    public let staleAfter: Double?

    public init(
        feature   : String,
        surface   : PluginSurfaceKind,
        document  : PluginDocument?,
        staleAfter: Double? = nil
    ) throws {
        self.feature    = feature
        self.surface    = surface
        self.document   = document
        self.staleAfter = staleAfter

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        feature       = try container.decode(String.self, forKey: .feature)
        surface       = try container.decode(PluginSurfaceKind.self, forKey: .surface)
        document      = try container.decodeIfPresent(PluginDocument.self, forKey: .document)
        staleAfter    = try container.decodeIfPresent(Double.self, forKey: .staleAfter)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(ContractValidation.identifier(feature), "Invalid feature ID")
        try ContractValidation.require(
            staleAfter.map { $0.isFinite && $0 >= 1 && $0 <= Self.maximumStaleAfter } ?? true,
            "Stale interval must be between a second and a day"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case feature
        case surface
        case document
        case staleAfter
    }
}
