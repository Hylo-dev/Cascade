//
//  PluginOutput.swift
//  CascadeKit
//

import Foundation

/// PluginOutput is a plugin's whole answer to one event: the publications that changed and,
/// when it needs one, the moment it wants to be woken next. `wake` replaces the one the
/// previous output asked for and no `wake` cancels it, so the wake a plugin holds is always the
/// one it asked for last. Each feature and surface appears at most once, and a plugin has at
/// most sixteen features on three surfaces.
public struct PluginOutput: Codable, Equatable, Sendable {

    public static let maximumPublications = 48

    public let publications: [PluginPublication]
    public let wake        : Date?

    public init(
        publications: [PluginPublication] = [],
        wake        : Date? = nil
    ) throws {
        self.publications = publications
        self.wake         = wake

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        publications  = try container.decodeIfPresent([PluginPublication].self, forKey: .publications) ?? []
        wake          = try container.decodeIfPresent(Date.self, forKey: .wake)

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(publications.count <= Self.maximumPublications, "Too many publications")
        try ContractValidation.require(
            Set(publications.map { [$0.feature, $0.surface.rawValue] }).count == publications.count,
            "A feature publishes once per surface"
        )
        if let wake {
            try ContractValidation.finite(wake)
        }
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case publications
        case wake
    }
}
