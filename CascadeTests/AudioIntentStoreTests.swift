//
//  AudioIntentStoreTests.swift
//  CascadeTests
//

import CascadeContracts
import Foundation
import Testing
@testable import Cascade

struct AudioIntentStoreTests {

    private func makeStore(_ body: (AudioIntentStore, UserDefaults) throws -> Void) rethrows {
        let suiteName = "CascadeTests.AudioIntentStore." + UUID().uuidString
        let defaults  = UserDefaults(suiteName: suiteName) ?? .standard
        defer { defaults.removePersistentDomain(forName: suiteName) }

        try body(AudioIntentStore(defaults: defaults), defaults)
    }

    @Test
    func intentsRoundTrip() throws {
        try makeStore { store, defaults in
            let music  = try AudioAppIdentity(bundleID: "com.apple.Music")
            let safari = try AudioAppIdentity(bundleID: "com.apple.Safari")
            let saved  = [
                music : try AudioAppIntent(gain: 0.25, isMuted: false, outputUIDs: ["speakers", "airpods"]),
                safari: try AudioAppIntent(gain: 1, isMuted: true, outputUIDs: [])
            ]

            store.save(saved)

            #expect(store.load() == saved)
            #expect(AudioIntentStore(defaults: defaults).load() == saved)
        }
    }

    @Test
    func neutralIntentsAreNotStored() throws {
        try makeStore { store, _ in
            let music  = try AudioAppIdentity(bundleID: "com.apple.Music")
            let safari = try AudioAppIdentity(bundleID: "com.apple.Safari")
            let loud   = try AudioAppIntent(gain: 0.5, isMuted: false, outputUIDs: [])

            store.save([music: .neutral, safari: loud])

            #expect(store.load() == [safari: loud])
        }
    }

    @Test
    func nothingStoredLoadsEmpty() {
        makeStore { store, _ in
            #expect(store.load().isEmpty)
        }
    }

    @Test
    func oneBadEntryDoesNotCostTheOthers() throws {
        try makeStore { store, defaults in
            let json = """
            [
              {"identity": {"bundleID": "com.apple.Music"}, "intent": {"gain": 0.4, "isMuted": false, "outputUIDs": []}},
              {"identity": {"bundleID": "com.apple.Safari"}, "intent": {"gain": 7, "isMuted": false, "outputUIDs": []}},
              {"nonsense": true}
            ]
            """
            defaults.set(Data(json.utf8), forKey: "audioAppIntents")

            let music = try AudioAppIdentity(bundleID: "com.apple.Music")

            #expect(store.load() == [music: try AudioAppIntent(gain: 0.4, isMuted: false, outputUIDs: [])])
        }
    }

    @Test
    func garbageLoadsEmpty() {
        makeStore { store, defaults in
            defaults.set(Data("not json".utf8), forKey: "audioAppIntents")

            #expect(store.load().isEmpty)
        }
    }
}
