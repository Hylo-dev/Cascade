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
        #expect(nodes.contains { $0.kind == .button(action: "caffeinate.options") })
        #expect(nodes.contains { $0.kind == .button(action: "caffeinate.duration.15") })
        #expect(nodes.contains { $0.kind == .toggle(isOn: true, action: "caffeinate.display") })
        #expect(!nodes.contains { $0.kind == .button(action: "caffeinate.stop") })
        #expect(nodes.contains { $0.kind == .symbol(name: "cup.and.saucer") })
        #expect(nodes.contains { $0.kind == .viewThatFits(axes: .both) })
        #expect(!PluginNodeTable(try PluginDocument(root: document.root)).entries.contains { $0.kind == .shape(.capsule) })
        #expect(nodes.filter { ["#full.cup:symbol", "#compact.cup:symbol"].contains($0.id.rawValue) }.allSatisfy {
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
        #expect(!PluginNodeTable(document).entries.contains { if case .toggle = $0.kind { return true }; return false })
        #expect(PluginNodeTable(document).entries.contains { $0.kind == .text("Updating…") })
        let malformed = try PluginSourceEvent(source: "caffeinate", fields: ["isActive": .bool(true)])
        #expect(PluginCaffeinateState(malformed) == nil)
        #expect(try plugin.handle(.source(malformed), context: PluginContext(plugin: owner)).publications.isEmpty)
    }

    @Test
    func activeOptionsExposeStopAndCreditsAndRejectMalformedPreferences() throws {
        let owner = try #require(PluginID(rawValue: "com.cascade.caffeinate"))
        let state = PluginCaffeinateState(isActive: true, keepDisplayAwake: false, minutes: 30, showsCredits: true)
        let output = try CaffeinatePlugin().handle(.source(state.event()), context: PluginContext(plugin: owner))
        let nodes = PluginNodeTable(try #require(output.publications.first?.document)).entries
        #expect(nodes.contains { $0.kind == .button(action: "caffeinate.stop") })
        #expect(nodes.contains { $0.kind == .toggle(isOn: false, action: "caffeinate.display") })
        #expect(nodes.contains {
            if case .text(let text) = $0.kind { return text.contains("Vorssaint") && text.contains("William Gustafson") }
            return false
        })
        var fields = try state.event().fields
        fields["minutes"] = .number(17)
        #expect(PluginCaffeinateState(try PluginSourceEvent(source: "caffeinate", fields: fields)) == nil)
        fields["minutes"] = .number(30)
        fields["showsCredits"] = .number(1)
        #expect(PluginCaffeinateState(try PluginSourceEvent(source: "caffeinate", fields: fields)) == nil)
    }
}
