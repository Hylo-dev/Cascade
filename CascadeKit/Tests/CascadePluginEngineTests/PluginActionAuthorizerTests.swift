//
//  PluginActionAuthorizerTests.swift
//  CascadeKit
//

import CascadeContracts
import Testing

@testable import CascadePluginEngine

@Suite
struct PluginActionAuthorizerTests {

    @Test
    func optionsUseTheSameDeclaredControlAndRevisionAuthorization() throws {
        let key = PluginPublicationKey(plugin: PluginEngineFixtures.clockID, feature: "test", surface: .widget)
        let document = try PluginDocument(
            root         : PluginNode(.button(action: "open"), id: "open"),
            optionsRoot  : PluginNode(.toggle(isOn: true, action: "display"), id: "display"),
            optionsAction: "open"
        )
        let feature = try PluginFeature(id: "test", surfaces: PluginSurfaces(widget: PluginWidgetSurface(sizes: [PluginWidgetSize(columns: 1, rows: 1)])), actions: ["open", "display"], supportsFullscreen: true)
        var store = PluginPublicationStore()
        _ = store.apply(document, staleAfter: nil, for: key, at: .now)
        let request = PluginActionRequest(key: key, node: PluginNodeID(rawValue: "#display:toggle"), revision: 1, value: .bool(false))
        #expect(PluginActionAuthorizer.event(for: request, entry: store[key], feature: feature) == (try PluginActionEvent(feature: "test", action: "display", value: .bool(false))))
        let stale = PluginActionRequest(key: key, node: request.node, revision: 0, value: .bool(false))
        #expect(PluginActionAuthorizer.event(for: stale, entry: store[key], feature: feature) == nil)
        let wrongValue = PluginActionRequest(key: key, node: request.node, revision: 1, value: .number(0))
        #expect(PluginActionAuthorizer.event(for: wrongValue, entry: store[key], feature: feature) == nil)
        let undeclared = try PluginFeature(id: "test", surfaces: feature.surfaces, actions: ["open"], supportsFullscreen: true)
        #expect(PluginActionAuthorizer.event(for: request, entry: store[key], feature: undeclared) == nil)
    }

    private let key = PluginPublicationKey(plugin: PluginEngineFixtures.musicID, feature: "now-playing", surface: .activity)

    private func entry() throws -> PluginPublicationStore.Entry? {
        var store = PluginPublicationStore()
        _ = store.apply(try PluginEngineFixtures.controls(), staleAfter: nil, for: key, at: PluginEngineFixtures.start.wall)
        return store[key]
    }

    private func event(
        _ node  : String,
        value   : PluginValue? = nil,
        revision: UInt64 = 1
    ) throws -> PluginActionEvent? {
        PluginActionAuthorizer.event(
            for    : PluginActionRequest(key: key, node: PluginNodeID(rawValue: node), revision: revision, value: value),
            entry  : try entry(),
            feature: try PluginEngineFixtures.music().features[0]
        )
    }

    @Test
    func theEventCarriesTheActionTheDocumentNamed() throws {
        #expect(try event("#next:button") == PluginActionEvent(feature: "now-playing", action: "next"))
        #expect(
            try event("#play:toggle", value: .bool(false))
                == PluginActionEvent(feature: "now-playing", action: "togglePlayback", value: .bool(false))
        )
        #expect(
            try event("#volume:slider", value: .number(0.25))
                == PluginActionEvent(feature: "now-playing", action: "setVolume", value: .number(0.25))
        )
    }

    @Test
    func aStaleRevisionFindsNothing() throws {
        #expect(try event("#next:button", revision: 2) == nil)
    }

    @Test
    func aValueOfTheWrongTypeFindsNothing() throws {
        #expect(try event("#next:button", value: .bool(true)) == nil)
        #expect(try event("#play:toggle", value: .number(1)) == nil)
        #expect(try event("#play:toggle") == nil)
    }

    @Test
    func aSliderValueOutsideItsRangeFindsNothing() throws {
        #expect(try event("#volume:slider", value: .number(1.5)) == nil)
    }

    @Test
    func aNodeThatIsNotAControlFindsNothing() throws {
        #expect(try event("#title:text") == nil)
        #expect(try event("#missing:button") == nil)
    }

    @Test
    func anActionTheFeatureDidNotDeclareFindsNothing() throws {
        let feature = try PluginFeature(id: "now-playing", surfaces: PluginSurfaces(activity: PluginPlainSurface()), actions: ["next"])
        let request = PluginActionRequest(key: key, node: PluginNodeID(rawValue: "#play:toggle"), revision: 1, value: .bool(true))

        #expect(PluginActionAuthorizer.event(for: request, entry: try entry(), feature: feature) == nil)
    }
}
