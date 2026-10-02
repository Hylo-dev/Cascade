//
//  PluginResources.swift
//  CascadeKit
//

import Foundation

/// PluginResources is the manifest's resource declaration. The limits themselves belong to the
/// host (spec §13), so only the profile is declared.
public struct PluginResources: Codable, Equatable, Sendable {

    public let profile: PluginResourceProfile

    public init(profile: PluginResourceProfile) {
        self.profile = profile
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        profile       = try container.decode(PluginResourceProfile.self, forKey: .profile)
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case profile
    }
}
