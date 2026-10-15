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

    /// explicit is the identity of the node of kind `kindName` that the plugin gave the explicit
    /// `id`. It is the one place the form is written, for the table that builds identities and
    /// for the kernel's views that look a node up by the id a plugin named.
    public static func explicit(
        _ id    : String,
        kindName: String
    ) -> PluginNodeID {
        PluginNodeID(rawValue: "#" + id + ":" + kindName)
    }
}
