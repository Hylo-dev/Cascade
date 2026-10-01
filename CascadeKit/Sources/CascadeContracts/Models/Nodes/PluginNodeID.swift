//
//  PluginNodeID.swift
//  CascadeKit
//

/// PluginNodeID is a node's identity within one publication: `#`, the explicit id and the kind
/// when the plugin set an id, otherwise its parent's identity, its position and its kind.
public struct PluginNodeID: RawRepresentable, Hashable, Sendable {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
