//
//  PluginNodeTableTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct PluginNodeTableTests {

    func table(_ root: PluginNode) throws -> PluginNodeTable {
        PluginNodeTable(try PluginDocument(root: root))
    }

    @Test
    func flattensDepthFirstWithStructuralIdentities() throws {
        let table = try table(PluginNodeFixtures.musicRow())
        let ids   = table.entries.map(\.id.rawValue)

        #expect(ids == [
            "root:hStack",
            "root:hStack/0:asset",
            "root:hStack/1:vStack",
            "root:hStack/1:vStack/0:text",
            "root:hStack/1:vStack/1:text",
            "root:hStack/2:spacer",
            "root:hStack/3:toggle",
            "root:hStack/3:toggle/0:symbol",
        ])
        #expect(table.root.children.map { table.entries[$0].id.rawValue } == ids.filter { $0.split(separator: "/").count == 2 })
    }

    @Test
    func explicitIdentityReplacesThePathAndAnchorsDescendants() throws {
        let root  = PluginNode(
            .vStack(alignment: .center, spacing: nil),
            children: [PluginNode(.hStack(alignment: .center, spacing: nil), id: "row", children: [PluginNode(.text("a"))])]
        )
        let table = try table(root)

        #expect(table.entries.map(\.id.rawValue) == ["root:vStack", "#row", "#row/0:text"])
    }

    @Test
    func layersGetTheirOwnSlotAfterTheChildren() throws {
        let root  = PluginNode(
            .zStack(alignment: .center),
            modifiers: [.background(alignment: .center)],
            children : [PluginNode(.text("a"))],
            layers   : [PluginNode(.shape(.capsule))]
        )
        let table = try table(root)

        #expect(table.entries.map(\.id.rawValue) == ["root:zStack", "root:zStack/0:text", "root:zStack/layer0:shape"])
        #expect(table.root.layers == [2])
    }

    @Test
    func equalNodesHashEqualAndAModifierChangesThePropertyHash() throws {
        let first  = try table(PluginNodeFixtures.musicRow())
        let second = try table(PluginNodeFixtures.musicRow())
        let paused = try table(PluginNodeFixtures.musicRow(isPlaying: false))

        #expect(first.entries.map(\.propertyHash) == second.entries.map(\.propertyHash))
        #expect(first.root.subtreeHash == second.root.subtreeHash)
        #expect(first.root.subtreeHash != paused.root.subtreeHash)
        #expect(first.root.propertyHash == paused.root.propertyHash)
    }

    @Test
    func aDeepChangeMovesOnlyItsAncestorsSubtreeHashes() throws {
        let before = try table(PluginNodeFixtures.musicRow(title: "One"))
        let after  = try table(PluginNodeFixtures.musicRow(title: "Two"))

        for (old, new) in zip(before.entries, after.entries) {
            let onPath = ["root:hStack", "root:hStack/1:vStack", "root:hStack/1:vStack/0:text"].contains(new.id.rawValue)

            #expect((old.subtreeHash != new.subtreeHash) == onPath)
        }
    }

    @Test
    func findsEntriesByIdentity() throws {
        let table = try table(PluginNodeFixtures.musicRow())

        #expect(table.index(of: PluginNodeID(rawValue: "root:hStack/2:spacer")) == 5)
        #expect(table.index(of: PluginNodeID(rawValue: "missing")) == nil)
    }
}
