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

    private let context = PluginContext(plugin: CaffeinatePlugin.id)

    @Test
    func theWidgetOffersACupSwitchAndAnOptionsPageWithoutScheduledWakes() throws {
        let output   = try CaffeinatePlugin().handle(.source(PluginCaffeinateState().event()), context: context)
        let document = try #require(output.publications.first?.document)
        let nodes    = PluginNodeTable(document).entries

        #expect(output.publications.first?.surface == .widget)
        #expect(output.wake == nil)
        #expect(document.optionsAction == "caffeinate.options")
        #expect(nodes.contains { $0.kind == .button(action: "caffeinate.options") })
        #expect(nodes.filter { $0.kind == .toggle(isOn: false, action: "caffeinate.toggle") }.count == 3)
        #expect(nodes.contains { $0.kind == .toggle(isOn: true, action: "caffeinate.display") })
        for minutes in CaffeinateCommand.durations {
            #expect(nodes.contains { $0.kind == .button(action: "caffeinate.duration.\(minutes)") })
        }
        #expect(nodes.filter { $0.kind == .symbol(name: "cup.and.saucer") }.allSatisfy {
            $0.modifiers.contains(.contentTransition(.symbolEffect))
        })
        #expect(!nodes.contains { if case .timer = $0.kind { return true }; return false })

        let manifest = try #require(FirstPartyPlugins.manifests().first { $0.id == CaffeinatePlugin.id })
        let feature  = try #require(manifest.features.first)
        #expect(feature.supportsFullscreen)
        #expect(feature.sources == [PluginCaffeinateState.source])
        for entry in nodes {
            switch entry.kind {
                case .button(let action), .toggle(_, let action):
                    #expect(feature.actions.contains(action))

                default:
                    break
            }
        }
    }

    /// A state change must update controls in place: their identities never carry the state,
    /// so the renderer keeps every control's view and only the changed content is redrawn.
    @Test
    func controlsKeepTheirIdentityAcrossSessionChanges() throws {
        func controls(_ state: PluginCaffeinateState) throws -> Set<PluginNodeID> {
            let output = try CaffeinatePlugin().handle(.source(state.event()), context: context)
            let table  = PluginNodeTable(try #require(output.publications.first?.document))
            return Set(table.entries.filter {
                switch $0.kind {
                    case .button, .toggle: true
                    default              : false
                }
            }.map(\.id))
        }

        let idle = try controls(PluginCaffeinateState())
        #expect(idle == (try controls(PluginCaffeinateState(isBusy: true))))
        #expect(idle == (try controls(PluginCaffeinateState(isActive: true, until: .now.addingTimeInterval(900), minutes: 15))))
        #expect(idle.contains(PluginNodeID(rawValue: "#power.options:toggle")))
        #expect(idle.contains(PluginNodeID(rawValue: "#duration.30:button")))
    }

    @Test
    func aTimedSessionShowsItsEndAndCountdownDrawnByTheKernel() throws {
        let until  = Date(timeIntervalSince1970: 2_000_000_000)
        let state  = PluginCaffeinateState(isActive: true, keepDisplayAwake: false, until: until, minutes: 30)
        let output = try CaffeinatePlugin().handle(.source(state.event()), context: context)
        let nodes  = PluginNodeTable(try #require(output.publications.first?.document)).entries

        #expect(output.wake == nil)
        #expect(nodes.contains { $0.kind == .timer(start: until.addingTimeInterval(-1_800), end: until, countsDown: true) })
        #expect(nodes.contains { $0.kind == .date(until, style: .time) })
        #expect(nodes.filter { $0.kind == .toggle(isOn: true, action: "caffeinate.toggle") }.count == 3)
        #expect(nodes.contains { $0.kind == .toggle(isOn: false, action: "caffeinate.display") })
    }

    @Test
    func aRepeatedStateIsNotPublishedAgainButARefreshIs() throws {
        let plugin = CaffeinatePlugin()
        let event  = try PluginCaffeinateState(isActive: true).event()

        #expect(try plugin.handle(.refresh, context: context).publications.isEmpty)
        #expect(try plugin.handle(.source(event), context: context).publications.count == 1)
        #expect(try plugin.handle(.source(event), context: context).publications.isEmpty)
        #expect(try plugin.handle(.refresh, context: context).publications.count == 1)
    }

    @Test
    func commandsDecodeOnlyTheWidgetsControlsAsAbsoluteRequests() {
        for node in ["#power.large:toggle", "#power.small:toggle", "#power.options:toggle"] {
            #expect(CaffeinateCommand(node: node, value: .bool(true)) == .setActive(true))
            #expect(CaffeinateCommand(node: node, value: .bool(false)) == .setActive(false))
            #expect(CaffeinateCommand(node: node, value: nil) == nil)
        }
        #expect(CaffeinateCommand(node: "#display:toggle", value: .bool(false)) == .setKeepsDisplayAwake(false))
        #expect(CaffeinateCommand(node: "#display:toggle", value: .number(1)) == nil)
        #expect(CaffeinateCommand(node: "#duration.120:button", value: nil) == .setDuration(minutes: 120))
        #expect(CaffeinateCommand(node: "#duration.17:button", value: nil) == nil)
        #expect(CaffeinateCommand(node: "#options:button", value: nil) == nil)
    }

    @Test
    func busyAndFailedStatesKeepControlsAndMalformedStateIsRejected() throws {
        let busy = try CaffeinatePlugin().handle(.source(PluginCaffeinateState(isBusy: true).event()), context: context)
        let busyNodes = PluginNodeTable(try #require(busy.publications.first?.document)).entries
        #expect(busyNodes.contains { $0.kind == .text("Updating…") })
        #expect(busyNodes.contains { $0.modifiers.contains(.opacity(0.5)) })

        let failed = try CaffeinatePlugin().handle(.source(PluginCaffeinateState(error: "No assertion").event()), context: context)
        #expect(PluginNodeTable(try #require(failed.publications.first?.document)).entries.contains { $0.kind == .text("No assertion") })

        let malformed = try PluginSourceEvent(source: "caffeinate", fields: ["isActive": .bool(true)])
        #expect(PluginCaffeinateState(malformed) == nil)
        #expect(try CaffeinatePlugin().handle(.source(malformed), context: context).publications.isEmpty)

        var fields = try PluginCaffeinateState(minutes: 30).event().fields
        fields["minutes"] = .number(17)
        #expect(PluginCaffeinateState(try PluginSourceEvent(source: "caffeinate", fields: fields)) == nil)
    }
}
