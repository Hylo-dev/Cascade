//
//  PluginActionAuthorizerTests.swift
//  CascadeKit
//

import CascadeContracts
import Testing

@testable import CascadePluginEngine

@Suite
struct PluginActionAuthorizerTests {

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
