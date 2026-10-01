//
//  PluginNodeID.swift
//  CascadeKit
//

/// PluginNodeID is a node's identity within one publication: `#` and the explicit id when the
/// plugin set one, otherwise its parent's identity, its position and its kind.
public struct PluginNodeID: RawRepresentable, Hashable, Sendable {

    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
