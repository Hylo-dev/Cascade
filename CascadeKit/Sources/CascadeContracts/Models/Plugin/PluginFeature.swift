//
//  PluginFeature.swift
//  CascadeKit
//

import Foundation

/// PluginFeature is one thing a plugin does, with everything it needs declared up front: the
/// surfaces it fills, the sources that wake it, the services it calls, the tier-2 components it
/// shows, its permissions and the actions its controls send. Declared means required: if the
/// host lacks any of them, the feature disables itself, and anything undeclared is denied.
public struct PluginFeature: Codable, Equatable, Sendable {

    public let id         : String
    public let surfaces   : PluginSurfaces
    public let sources    : [String]
    public let services   : [String]
    public let components : [PluginComponentReference]
    public let permissions: [String]
    public let actions    : [String]
    public let supportsFullscreen: Bool

    public init(
        id         : String,
        surfaces   : PluginSurfaces,
        sources    : [String] = [],
        services   : [String] = [],
        components : [PluginComponentReference] = [],
        permissions: [String] = [],
        actions    : [String] = [],
        supportsFullscreen: Bool = false
    ) throws {
        self.id          = id
        self.surfaces    = surfaces
        self.sources     = sources
        self.services    = services
        self.components  = components
        self.permissions = permissions
        self.actions     = actions
        self.supportsFullscreen = supportsFullscreen

        try validate()
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        id            = try container.decode(String.self, forKey: .id)
        surfaces      = try container.decode(PluginSurfaces.self, forKey: .surfaces)
        sources       = try container.decodeIfPresent([String].self, forKey: .sources) ?? []
        services      = try container.decodeIfPresent([String].self, forKey: .services) ?? []
        components    = try container.decodeIfPresent([PluginComponentReference].self, forKey: .components) ?? []
        permissions   = try container.decodeIfPresent([String].self, forKey: .permissions) ?? []
        actions       = try container.decodeIfPresent([String].self, forKey: .actions) ?? []
        supportsFullscreen = try container.decodeIfPresent(Bool.self, forKey: .supportsFullscreen) ?? false

        try validate()
    }

    public func validate() throws {
        try ContractValidation.require(!supportsFullscreen || surfaces.widget != nil, "Fullscreen requires a widget")
        try ContractValidation.require(ContractValidation.identifier(id), "Invalid feature ID")

        try ContractValidation.unique(sources, "Duplicate sources")
        try ContractValidation.require(sources.allSatisfy(PluginCatalog.sources.contains), "Unknown source")

        try ContractValidation.unique(services, "Duplicate services")
        try ContractValidation.require(services.allSatisfy(ContractValidation.identifier), "Invalid service ID")

        try ContractValidation.unique(components.map(\.id), "Duplicate components")
        try ContractValidation.require(
            components.allSatisfy { component in
                PluginCatalog.components[component.id].map { component.version <= $0 } ?? false
            },
            "Unknown component or version"
        )

        try ContractValidation.unique(permissions, "Duplicate permissions")
        try ContractValidation.require(permissions.allSatisfy(ContractValidation.identifier), "Invalid permission ID")

        try ContractValidation.unique(actions, "Duplicate actions")
        try ContractValidation.require(actions.allSatisfy(ContractValidation.identifier), "Invalid action ID")
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case id
        case surfaces
        case sources
        case services
        case components
        case permissions
        case actions
        case supportsFullscreen
    }

    /// encode preserves the legacy wire representation until fullscreen is explicitly granted.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(surfaces, forKey: .surfaces)
        try container.encode(sources, forKey: .sources)
        try container.encode(services, forKey: .services)
        try container.encode(components, forKey: .components)
        try container.encode(permissions, forKey: .permissions)
        try container.encode(actions, forKey: .actions)
        if supportsFullscreen { try container.encode(true, forKey: .supportsFullscreen) }
    }
}
