//
//  PluginNoticeAttributes.swift
//  CascadeKit
//

import Foundation

/// PluginNoticeAttributes is what a notice says about itself beside its regions: how long it
/// shows, at most ten seconds; the rim's tint while it does; the width it would like for each
/// compact side; the sentence VoiceOver reads for it; and whether it is a new event or only
/// updates the notice on screen.
public struct PluginNoticeAttributes: Codable, Hashable, Sendable {

    public static let durations     = 1.0...10.0
    public static let compactWidths = 24.0...400.0

    public let duration          : Double
    public let border            : PluginBorderTint?
    public let compactWidth      : Double?
    public let accessibilityLabel: String
    public let delivery          : PluginNoticeDelivery

    public init(
        duration          : Double,
        border            : PluginBorderTint? = nil,
        compactWidth      : Double? = nil,
        accessibilityLabel: String,
        delivery          : PluginNoticeDelivery = .show
    ) throws {
        self.duration           = duration
        self.border             = border
        self.compactWidth       = compactWidth
        self.accessibilityLabel = accessibilityLabel
        self.delivery           = delivery

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container      = try decoder.container(keyedBy: CodingKeys.self)
        duration           = try container.decode(Double.self, forKey: .duration)
        border             = try container.decodeIfPresent(PluginBorderTint.self, forKey: .border)
        compactWidth       = try container.decodeIfPresent(Double.self, forKey: .compactWidth)
        accessibilityLabel = try container.decode(String.self, forKey: .accessibilityLabel)
        delivery           = try container.decodeIfPresent(PluginNoticeDelivery.self, forKey: .delivery) ?? .show

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(Self.durations.contains(duration), "A notice shows for one to ten seconds")
        try ContractValidation.require(
            compactWidth.map { Self.compactWidths.contains($0) } ?? true,
            "A notice's compact width is 24 to 400 points"
        )
        try ContractValidation.require(
            !accessibilityLabel.isEmpty && accessibilityLabel.utf8.count <= 512,
            "A notice needs an accessibility label of at most 512 bytes"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case duration
        case border
        case compactWidth
        case accessibilityLabel
        case delivery
    }
}
