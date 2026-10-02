//
//  PluginPublication.swift
//  CascadeKit
//

import Foundation

/// PluginPublication is what one feature shows on one surface. A document replaces whatever the
/// feature showed there; no document withdraws it. `staleAfter` says, in seconds, how old the
/// content may grow before the kernel asks for a fresh one when the surface becomes visible
/// again. Content the kernel draws itself, such as a clock face, never goes stale, so it leaves
/// `staleAfter` out. A notice's document is its regions, and its publication carries the notice's
/// attributes; no other publication carries them.
public struct PluginPublication: Codable, Equatable, Sendable {

    public static let maximumStaleAfter = 86_400.0

    public let feature   : String
    public let surface   : PluginSurfaceKind
    public let document  : PluginDocument?
    public let staleAfter: Double?
    public let notice    : PluginNoticeAttributes?

    public init(
        feature   : String,
        surface   : PluginSurfaceKind,
        document  : PluginDocument?,
        staleAfter: Double? = nil,
        notice    : PluginNoticeAttributes? = nil
    ) throws {
        self.feature    = feature
        self.surface    = surface
        self.document   = document
        self.staleAfter = staleAfter
        self.notice     = notice

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        feature       = try container.decode(String.self, forKey: .feature)
        surface       = try container.decode(PluginSurfaceKind.self, forKey: .surface)
        document      = try container.decodeIfPresent(PluginDocument.self, forKey: .document)
        staleAfter    = try container.decodeIfPresent(Double.self, forKey: .staleAfter)
        notice        = try container.decodeIfPresent(PluginNoticeAttributes.self, forKey: .notice)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(ContractValidation.identifier(feature), "Invalid feature ID")
        try ContractValidation.require(
            staleAfter.map { $0.isFinite && $0 >= 1 && $0 <= Self.maximumStaleAfter } ?? true,
            "Stale interval must be between a second and a day"
        )

        if let document {
            try ContractValidation.require(
                (surface == .notice) == (notice != nil),
                "A notice carries its attributes, and only a notice does"
            )
            try ContractValidation.require(
                (surface == .notice) == (document.root.kind == .regions),
                "A notice's document is its regions, and only a notice's"
            )
        } else {
            try ContractValidation.require(notice == nil, "A withdrawal carries no attributes")
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case feature
        case surface
        case document
        case staleAfter
        case notice
    }
}
