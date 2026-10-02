//
//  PluginSurfaces.swift
//  CascadeKit
//

import Foundation

/// PluginSurfaces lists where a feature can appear: an activity, a widget, a notice, or any
/// mix of them. A feature with no surface could never be seen, so it is rejected.
public struct PluginSurfaces: Codable, Equatable, Sendable {

    public let activity: PluginPlainSurface?
    public let widget  : PluginWidgetSurface?
    public let notice  : PluginPlainSurface?

    public init(
        activity: PluginPlainSurface? = nil,
        widget  : PluginWidgetSurface? = nil,
        notice  : PluginPlainSurface? = nil
    ) throws {
        self.activity = activity
        self.widget   = widget
        self.notice   = notice

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        activity      = try container.decodeIfPresent(PluginPlainSurface.self, forKey: .activity)
        widget        = try container.decodeIfPresent(PluginWidgetSurface.self, forKey: .widget)
        notice        = try container.decodeIfPresent(PluginPlainSurface.self, forKey: .notice)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(
            activity != nil || widget != nil || notice != nil,
            "A feature declares at least one surface"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case activity
        case widget
        case notice
    }
}
