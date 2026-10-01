//
//  PluginNode.swift
//  CascadeKit
//

import Foundation

/// PluginNode is one node of a plugin document, shaped like a SwiftUI view: a kind, its
/// modifiers in SwiftUI's order, its children, and the content of its overlay and background
/// modifiers as layers. It is the same value in process and on the wire. Identity is
/// structural unless `id` is set, as with SwiftUI's `.id()`.
public struct PluginNode: Codable, Hashable, Sendable {

    public let kind     : PluginNodeKind
    public let id       : String?
    public let modifiers: [PluginModifier]
    public let children : [PluginNode]
    public let layers   : [PluginNode]

    public init(
        _ kind   : PluginNodeKind,
        id       : String? = nil,
        modifiers: [PluginModifier] = [],
        children : [PluginNode] = [],
        layers   : [PluginNode] = []
    ) {
        self.kind      = kind
        self.id        = id
        self.modifiers = modifiers
        self.children  = children
        self.layers    = layers
    }

    public init(from decoder: any Decoder) throws {
        try ContractValidation.knownFields(in: decoder, CodingKeys.self)

        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind          = try container.decode(PluginNodeKind.self, forKey: .kind)
        id            = try container.decodeIfPresent(String.self, forKey: .id)
        modifiers     = try container.decodeIfPresent([PluginModifier].self, forKey: .modifiers) ?? []
        children      = try container.decodeIfPresent([PluginNode].self, forKey: .children) ?? []
        layers        = try container.decodeIfPresent([PluginNode].self, forKey: .layers) ?? []
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {

        case kind
        case id
        case modifiers
        case children
        case layers
    }
}
