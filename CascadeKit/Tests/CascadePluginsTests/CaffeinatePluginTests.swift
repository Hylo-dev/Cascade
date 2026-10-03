//
//  CaffeinatePluginTests.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginSDK
import Foundation
import Testing
@testable import CascadePlugins

struct CaffeinatePluginTests {

    @Test
    func theWidgetOffersACompactCupWithoutAPillOrScheduledWakes() throws {
        let plugin = CaffeinatePlugin()
        let owner = try #require(PluginID(rawValue: "com.cascade.caffeinate"))
        let state = PluginCaffeinateState()
        let output = try plugin.handle(.source(state.event()), context: PluginContext(plugin: owner))
        let document = try #require(output.publications.first?.document)
        let nodes = PluginNodeTable(document).entries

        #expect(output.publications.first?.surface == .widget)
        #expect(output.wake == nil)
        #expect(nodes.contains { $0.kind == .button(action: "caffeinate.toggle") })
        #expect(!nodes.contains { $0.kind == .button(action: "caffeinate.options") })
        #expect(nodes.filter { if case .button = $0.kind { return true }; return false }.count == 2)
        #expect(nodes.contains { $0.kind == .symbol(name: "cup.and.saucer") })
        #expect(nodes.contains { $0.kind == .viewThatFits(axes: .both) })
        #expect(!nodes.contains { $0.kind == .shape(.capsule) })
        #expect(nodes.filter { if case .symbol = $0.kind { return true }; return false }.allSatisfy {
            $0.modifiers.contains(.contentTransition(.symbolEffect))
        })
        #expect(PluginCaffeinateState(try state.event()) == state)
        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == owner })
        let sizes = try #require(manifest.features.first?.surfaces.widget?.sizes)
        #expect(sizes.allSatisfy { $0.columns <= 2 && $0.rows <= 2 })
        #expect(sizes.contains(try PluginWidgetSize(columns: 1, rows: 1)))
    }

    @Test
    func inFlightChangesInvalidateControlsAndMalformedStateCannotEnableThem() throws {
        let plugin = CaffeinatePlugin()
        let owner = try #require(PluginID(rawValue: "com.cascade.caffeinate"))
        let busy = PluginCaffeinateState(isBusy: true)
        let output = try plugin.handle(.source(busy.event()), context: PluginContext(plugin: owner))
        let document = try #require(output.publications.first?.document)
        #expect(!PluginNodeTable(document).entries.contains { if case .button = $0.kind { return true }; return false })
        #expect(!PluginNodeTable(document).entries.contains { $0.kind == .text("Updating…") })
        let malformed = try PluginSourceEvent(source: "caffeinate", fields: ["isActive": .bool(true)])
        #expect(PluginCaffeinateState(malformed) == nil)
        #expect(try plugin.handle(.source(malformed), context: PluginContext(plugin: owner)).publications.isEmpty)
    }
}
