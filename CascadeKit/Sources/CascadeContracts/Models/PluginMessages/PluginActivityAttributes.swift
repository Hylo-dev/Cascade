//
//  PluginActivityAttributes.swift
//  CascadeKit
//

import Foundation

/// PluginActivityAttributes is what an activity says about itself beside its regions: when it
/// started, how relevant it is from zero to one, and the sentence VoiceOver reads for it.
///
/// `startedAt` is the activity's identity over time: the kernel presents an activity again only
/// when it changes, so a plugin renews a lifetime by publishing a new start and keeps the
/// current one by repeating it. `relevance` is the plugin's own say in the order of competing
/// activities; the arbitration weighs it, it does not command it.
public struct PluginActivityAttributes: Codable, Hashable, Sendable {

    public static let relevances = 0.0...1.0

    public let startedAt         : Date
    public let relevance         : Double
    public let accessibilityLabel: String

    public init(
        startedAt         : Date,
        relevance         : Double,
        accessibilityLabel: String
    ) throws {
        self.startedAt          = startedAt
        self.relevance          = relevance
        self.accessibilityLabel = accessibilityLabel

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container      = try decoder.container(keyedBy: CodingKeys.self)
        startedAt          = try container.decode(Date.self, forKey: .startedAt)
        relevance          = try container.decode(Double.self, forKey: .relevance)
        accessibilityLabel = try container.decode(String.self, forKey: .accessibilityLabel)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.finite(startedAt)
        try ContractValidation.require(Self.relevances.contains(relevance), "An activity's relevance is between zero and one")
        try ContractValidation.require(
            !accessibilityLabel.isEmpty && accessibilityLabel.utf8.count <= 512,
            "An activity needs an accessibility label of at most 512 bytes"
        )
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case startedAt
        case relevance
        case accessibilityLabel
    }
}
