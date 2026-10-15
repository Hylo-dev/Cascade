//
//  PluginPublication.swift
//  CascadeKit
//

import Foundation

/// PluginPublication is what one feature shows on one surface. A document replaces whatever the
/// feature showed there; no document withdraws it. `staleAfter` says, in seconds, how old the
/// content may grow before the kernel asks for a fresh one when the surface becomes visible
/// again. Content the kernel draws itself, such as a clock face, never goes stale, so it leaves
/// `staleAfter` out. A notice's document is three regions; an activity's is three or four, the
/// fourth being the expanded presentation, and an activity without it never takes over the
/// opened notch. The publication carries the notice's or the activity's attributes; no other
/// publication carries either.
public struct PluginPublication: Codable, Equatable, Sendable {

    public static let maximumStaleAfter = 86_400.0

    public let feature   : String
    public let surface   : PluginSurfaceKind
    public let document  : PluginDocument?
    public let staleAfter: Double?
    public let notice    : PluginNoticeAttributes?
    public let activity  : PluginActivityAttributes?

    public init(
        feature   : String,
        surface   : PluginSurfaceKind,
        document  : PluginDocument?,
        staleAfter: Double? = nil,
        notice    : PluginNoticeAttributes? = nil,
        activity  : PluginActivityAttributes? = nil
    ) throws {
        self.feature    = feature
        self.surface    = surface
        self.document   = document
        self.staleAfter = staleAfter
        self.notice     = notice
        self.activity   = activity

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
        activity      = try container.decodeIfPresent(PluginActivityAttributes.self, forKey: .activity)

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
                (surface == .activity) == (activity != nil),
                "An activity carries its attributes, and only an activity does"
            )

            let regions = document.root.kind == .regions
            try ContractValidation.require(
                (surface == .notice || surface == .activity) == regions,
                "A notice's or an activity's document is its regions, and only theirs"
            )
            let regionCount = document.root.children.count
            try ContractValidation.require(
                !regions || (surface == .activity ? (3...4).contains(regionCount) : regionCount == 3),
                "A notice has three regions and an activity three or four"
            )
        } else {
            try ContractValidation.require(notice == nil && activity == nil, "A withdrawal carries no attributes")
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case feature
        case surface
        case document
        case staleAfter
        case notice
        case activity
    }
}
