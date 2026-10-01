//
//  PluginPublicationStoreTests.swift
//  CascadeKit
//

import CascadeContracts
import Testing

@testable import CascadePluginEngine

@Suite
struct PluginPublicationStoreTests {

    private let key   = PluginPublicationKey(plugin: PluginEngineFixtures.musicID, feature: "now-playing", surface: .activity)
    private let epoch = PluginEngineFixtures.start.wall

    @Test
    func theFirstPublicationInsertsEveryNode() throws {
        var store  = PluginPublicationStore()
        let change = store.apply(try PluginEngineFixtures.controls(), staleAfter: nil, for: key, at: epoch)

        #expect(change?.revision == 1)
        #expect(change?.content?.diff.inserted.count == 5)
    }

    @Test
    func anEqualDocumentChangesNothingButRenewsItsAge() throws {
        let song  = try PluginEngineFixtures.text("Song")
        var store = PluginPublicationStore()
        _ = store.apply(song, staleAfter: 60, for: key, at: epoch)
        let equal = store.apply(song, staleAfter: 60, for: key, at: epoch.addingTimeInterval(50))

        #expect(equal == nil)
        #expect(store[key]?.revision == 1)
        #expect(!store.isStale(key, at: epoch.addingTimeInterval(110)))
        #expect(store.isStale(key, at: epoch.addingTimeInterval(111)))
    }

    @Test
    func aChangeOfGlassLightsAloneIsDeliveredWithAnEmptyDiff() throws {
        let lit = try PluginDocument(
            root       : PluginNode(.text("Song")),
            glassLights: [GlassLight(x: 0.5, y: 0.5, radius: 0.3, red: 1, green: 0.5, blue: 0, intensity: 0.8)]
        )
        var store = PluginPublicationStore()
        _ = store.apply(try PluginEngineFixtures.text("Song"), staleAfter: nil, for: key, at: epoch)

        let change = store.apply(lit, staleAfter: nil, for: key, at: epoch)

        #expect(change?.revision == 2)
        #expect(change?.content?.diff.isEmpty == true)
    }

    @Test
    func withdrawingRemovesTheContentUnderANewRevision() throws {
        var store = PluginPublicationStore()
        _ = store.apply(try PluginEngineFixtures.text("Song"), staleAfter: nil, for: key, at: epoch)

        let change = store.withdraw(key)

        #expect(change?.revision == 2)
        #expect(change?.content == nil)
        #expect(store[key] == nil)
        #expect(store.withdraw(key) == nil)
    }

    @Test
    func contentWithoutAnIntervalOrStoredNowhereIsNeverStale() throws {
        var store = PluginPublicationStore()
        #expect(!store.isStale(key, at: epoch))

        _ = store.apply(try PluginEngineFixtures.text("12:00"), staleAfter: nil, for: key, at: epoch)

        #expect(!store.isStale(key, at: epoch.addingTimeInterval(1_000_000)))
    }

    @Test
    func renewingRestartsTheContentsAge() throws {
        var store = PluginPublicationStore()
        _ = store.apply(try PluginEngineFixtures.text("Song"), staleAfter: 60, for: key, at: epoch)

        store.renew(key, at: epoch.addingTimeInterval(100))

        #expect(!store.isStale(key, at: epoch.addingTimeInterval(150)))
        #expect(store[key]?.revision == 1)
    }

    @Test
    func keysListOnlyThePluginsOwnPublicationsInOrder() throws {
        let widget = PluginPublicationKey(plugin: PluginEngineFixtures.musicID, feature: "now-playing", surface: .widget)
        let other  = PluginPublicationKey(plugin: PluginEngineFixtures.clockID, feature: "time", surface: .widget)
        var store  = PluginPublicationStore()
        for target in [widget, other, key] {
            _ = store.apply(try PluginEngineFixtures.text("x"), staleAfter: nil, for: target, at: epoch)
        }

        #expect(store.keys(of: PluginEngineFixtures.musicID) == [key, widget])
    }
}
