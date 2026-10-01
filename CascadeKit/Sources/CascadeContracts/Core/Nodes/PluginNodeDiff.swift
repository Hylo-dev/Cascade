//
//  PluginNodeDiff.swift
//  CascadeKit
//

import Foundation

/// PluginNodeDiff is what changed between two revisions of one publication, by node identity:
/// the nodes to create, the nodes to drop, and the nodes to update because their own
/// properties, their children or their layers changed. The renderer touches only these nodes.
///
/// The walk follows the new table from the root and stops at any node whose subtree hash
/// equals the old one, so an unchanged subtree costs one comparison however large it is.
public struct PluginNodeDiff: Equatable, Sendable {

    public let inserted: [PluginNodeID]
    public let removed : [PluginNodeID]
    public let updated : [PluginNodeID]

    public var isEmpty: Bool {
        inserted.isEmpty && removed.isEmpty && updated.isEmpty
    }

    public init(
        from old: PluginNodeTable?,
        to new  : PluginNodeTable
    ) {
        guard let old else {
            inserted = new.entries.map(\.id)
            removed  = []
            updated  = []
            return
        }
        guard old.root.id != new.root.id || old.root.subtreeHash != new.root.subtreeHash else {
            inserted = []
            removed  = []
            updated  = []
            return
        }

        var inserted = [PluginNodeID]()
        var updated  = [PluginNodeID]()
        var pending  = [0]

        while let index = pending.popLast() {
            let entry = new.entries[index]
            if let previousIndex = old.index(of: entry.id) {
                let previous = old.entries[previousIndex]
                if previous.subtreeHash == entry.subtreeHash {
                    continue
                }

                let sameChildren = previous.children.map { old.entries[$0].id } == entry.children.map { new.entries[$0].id }
                let sameLayers   = previous.layers.map { old.entries[$0].id } == entry.layers.map { new.entries[$0].id }
                if previous.propertyHash != entry.propertyHash || !sameChildren || !sameLayers {
                    updated.append(entry.id)
                }
            } else {
                inserted.append(entry.id)
            }

            pending.append(contentsOf: (entry.children + entry.layers).reversed())
        }

        let present = Set(new.entries.map(\.id))

        self.inserted = inserted
        self.removed  = old.entries.map(\.id).filter { !present.contains($0) }
        self.updated  = updated
    }
}
