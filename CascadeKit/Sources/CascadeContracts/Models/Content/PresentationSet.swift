//
//  PresentationSet.swift
//  CascadeKit
//

import Foundation

/// PresentationSet is a validated value in the version 1 addon protocol.
public struct PresentationSet: Codable, Equatable, Sendable {

    public let widget         : ContentDocument?
    public let compactLeading : ContentDocument?
    public let compactTrailing: ContentDocument?
    public let minimal        : ContentDocument?
    public let expanded       : ContentDocument?

    public init(
        widget         : ContentDocument?,
        compactLeading : ContentDocument?,
        compactTrailing: ContentDocument?,
        minimal        : ContentDocument?,
        expanded       : ContentDocument?
    ) throws {
        self.widget          = widget
        self.compactLeading  = compactLeading
        self.compactTrailing = compactTrailing
        self.minimal         = minimal
        self.expanded        = expanded

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        let allKeys = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(allKeys.allKeys.map(\.stringValue)).isSubset(of: [
                "widget", "compactLeading", "compactTrailing", "minimal", "expanded",
            ]),
            "Unknown representation"
        )

        let fields = try decoder.container(keyedBy: WireKey.self)
        try ContractValidation.require(
            Set(fields.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))),
            "Unknown wire field"
        )

        let container   = try decoder.container(keyedBy: CodingKeys.self)
        widget          = try container.decodeIfPresent(ContentDocument.self, forKey: .widget)
        compactLeading  = try container.decodeIfPresent(ContentDocument.self, forKey: .compactLeading)
        compactTrailing = try container.decodeIfPresent(ContentDocument.self, forKey: .compactTrailing)
        minimal         = try container.decodeIfPresent(ContentDocument.self, forKey: .minimal)
        expanded        = try container.decodeIfPresent(ContentDocument.self, forKey: .expanded)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            widget != nil || compactLeading != nil || compactTrailing != nil
                || minimal != nil || expanded != nil,
            "Empty presentation set"
        )
        try ContractValidation.bytes(self, maximum: 65_536)
    }

    /// validateFamily enforces the required representations for one shared publication.
    public func validateFamily(_ kind: Publication.Kind) throws {
        switch kind {
            case .widget:
                try ContractValidation.require(widget != nil, "Widget representation is required")

            case .activity:
                try ContractValidation.require(
                    compactLeading != nil && compactTrailing != nil && minimal != nil && expanded != nil,
                    "Activity representations are required"
                )

            case .notice:
                try ContractValidation.require(
                    compactLeading != nil && compactTrailing != nil && minimal != nil && expanded == nil,
                    "Notice requires compact and minimal, without expanded"
                )
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case widget
        case compactLeading
        case compactTrailing
        case minimal
        case expanded
    }
}
