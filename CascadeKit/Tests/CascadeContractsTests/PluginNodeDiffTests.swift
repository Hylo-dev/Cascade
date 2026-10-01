//
//  PluginNodeDiffTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct PluginNodeDiffTests {

    func table(_ root: PluginNode) throws -> PluginNodeTable {
        PluginNodeTable(try PluginDocument(root: root))
    }

    func ids(_ values: [PluginNodeID]) -> [String] {
        values.map(\.rawValue)
    }

    @Test
    func theFirstRevisionInsertsEveryNode() throws {
        let new  = try table(PluginNodeFixtures.musicRow())
        let diff = PluginNodeDiff(from: nil, to: new)

        #expect(diff.inserted == new.entries.map(\.id))
        #expect(diff.removed.isEmpty && diff.updated.isEmpty)
    }

    @Test
    func anIdenticalRevisionChangesNothing() throws {
        let diff = PluginNodeDiff(from: try table(PluginNodeFixtures.musicRow()), to: try table(PluginNodeFixtures.musicRow()))

        #expect(diff.isEmpty)
    }

    @Test
    func aNewTitleUpdatesOnlyTheTitle() throws {
        let diff = PluginNodeDiff(
            from: try table(PluginNodeFixtures.musicRow(title: "One")),
            to  : try table(PluginNodeFixtures.musicRow(title: "Two"))
        )

        #expect(ids(diff.updated) == ["root:hStack/1:vStack/0:text"])
        #expect(diff.inserted.isEmpty && diff.removed.isEmpty)
    }

    @Test
    func addingAndRemovingChildrenUpdatesTheirParent() throws {
        let two   = try table(PluginNodeFixtures.stack(of: 2))
        let three = try table(PluginNodeFixtures.stack(of: 3))

        let added   = PluginNodeDiff(from: two, to: three)
        let removed = PluginNodeDiff(from: three, to: two)

        #expect(ids(added.inserted) == ["root:vStack/2:text"])
        #expect(ids(added.updated) == ["root:vStack"])
        #expect(ids(removed.removed) == ["root:vStack/2:text"])
        #expect(ids(removed.updated) == ["root:vStack"])
    }

    @Test
    func aKindChangeInTheSameSlotReplacesTheNode() throws {
        let before = try table(PluginNode(.hStack(alignment: .center, spacing: nil), children: [PluginNode(.text("x"))]))
        let after  = try table(PluginNode(.hStack(alignment: .center, spacing: nil), children: [PluginNode(.symbol(name: "x"))]))
        let diff   = PluginNodeDiff(from: before, to: after)

        #expect(ids(diff.removed) == ["root:hStack/0:text"])
        #expect(ids(diff.inserted) == ["root:hStack/0:symbol"])
        #expect(ids(diff.updated) == ["root:hStack"])
    }

    @Test
    func anExplicitlyIdentifiedNodeMovesWithoutBeingRecreated() throws {
        let badge  = PluginNode(.text("3"), id: "badge")
        let before = try table(PluginNode(
            .vStack(alignment: .center, spacing: nil),
            children: [PluginNode(.hStack(alignment: .center, spacing: nil), children: [badge]), PluginNode(.hStack(alignment: .center, spacing: nil))]
        ))
        let after  = try table(PluginNode(
            .vStack(alignment: .center, spacing: nil),
            children: [PluginNode(.hStack(alignment: .center, spacing: nil)), PluginNode(.hStack(alignment: .center, spacing: nil), children: [badge])]
        ))
        let diff   = PluginNodeDiff(from: before, to: after)

        #expect(diff.inserted.isEmpty && diff.removed.isEmpty)
        #expect(Set(ids(diff.updated)) == ["root:vStack/0:hStack", "root:vStack/1:hStack"])
    }

    @Test
    func aChangeInsideALayerUpdatesOnlyTheLayer() throws {
        func root(_ text: String) -> PluginNode {
            PluginNode(
                .zStack(alignment: .center),
                modifiers: [.overlay(alignment: .topTrailing)],
                children : [PluginNode(.symbol(name: "bell"))],
                layers   : [PluginNode(.text(text))]
            )
        }

        let diff = PluginNodeDiff(from: try table(root("1")), to: try table(root("2")))

        #expect(ids(diff.updated) == ["root:zStack/layer0:text"])
    }
}
