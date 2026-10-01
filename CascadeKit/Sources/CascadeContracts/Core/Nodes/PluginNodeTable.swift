//
//  PluginNodeTable.swift
//  CascadeKit
//

import Foundation

/// PluginNodeTable is a validated document flattened for diffing: one contiguous entry per
/// node, in depth-first order with each node's children before its layers. An entry keeps the
/// node's identity, its own kind and modifiers, the indices of its children and layers, and two
/// hashes. `propertyHash` covers the node alone; `subtreeHash` also covers every descendant's
/// identity and hash, so an unchanged subtree is recognised with one comparison.
///
/// The hashes come from Swift's `Hasher`, seeded per process. They are compared only inside the
/// kernel that computed them and never cross the wire, which carries full snapshots.
public struct PluginNodeTable: Sendable {

    /// Entry is one node of the table.
    public struct Entry: Sendable {

        public let id          : PluginNodeID
        public let kind        : PluginNodeKind
        public let modifiers   : [PluginModifier]
        public let children    : [Int]
        public let layers      : [Int]
        public let propertyHash: Int
        public let subtreeHash : Int
    }

    public let entries: [Entry]

    private let indices: [PluginNodeID: Int]

    public init(_ document: PluginDocument) {
        var entries = [Entry]()
        entries.reserveCapacity(PluginDocument.maximumNodes)
        Self.append(document.root, id: Self.identity(of: document.root, under: nil, at: "root"), into: &entries)

        self.entries = entries
        indices      = Dictionary(uniqueKeysWithValues: entries.enumerated().map { index, entry in (entry.id, index) })
    }

    public var root: Entry {
        entries[0]
    }

    public func index(of id: PluginNodeID) -> Int? {
        indices[id]
    }

    /// append writes the node's entry, then its subtree, and returns the entry's index. The
    /// entry is reserved first so that its index precedes its descendants'.
    @discardableResult
    private static func append(
        _ node      : PluginNode,
        id          : PluginNodeID,
        into entries: inout [Entry]
    ) -> Int {
        let index = entries.count
        entries.append(
            Entry(
                id          : id,
                kind        : node.kind,
                modifiers   : node.modifiers,
                children    : [],
                layers      : [],
                propertyHash: 0,
                subtreeHash : 0
            )
        )

        let children = node.children.enumerated().map { position, child in
            append(child, id: identity(of: child, under: id, at: "\(position)"), into: &entries)
        }
        let layers   = node.layers.enumerated().map { position, layer in
            append(layer, id: identity(of: layer, under: id, at: "layer\(position)"), into: &entries)
        }

        var properties = Hasher()
        properties.combine(node.kind)
        properties.combine(node.modifiers)

        let propertyHash = properties.finalize()

        var subtree = Hasher()
        subtree.combine(propertyHash)
        for descendant in children + layers {
            subtree.combine(entries[descendant].id)
            subtree.combine(entries[descendant].subtreeHash)
        }

        entries[index] = Entry(
            id          : id,
            kind        : node.kind,
            modifiers   : node.modifiers,
            children    : children,
            layers      : layers,
            propertyHash: propertyHash,
            subtreeHash : subtree.finalize()
        )

        return index
    }

    /// identity is `#` and the explicit id, or the parent's identity, the slot and the kind.
    private static func identity(
        of node     : PluginNode,
        under parent: PluginNodeID?,
        at slot     : String
    ) -> PluginNodeID {
        if let explicit = node.id {
            return PluginNodeID(rawValue: "#" + explicit)
        }

        let prefix = parent.map { $0.rawValue + "/" } ?? ""

        return PluginNodeID(rawValue: prefix + slot + ":" + node.kind.name)
    }
}
