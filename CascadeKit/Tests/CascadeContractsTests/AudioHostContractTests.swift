//
//  AudioHostContractTests.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import Testing

@Suite
struct AudioHostContractTests {

    private func identity(_ bundleID: String = "com.apple.Safari") throws -> AudioAppIdentity {
        try AudioAppIdentity(bundleID: bundleID)
    }

    @Test
    func intentRejectsNonFiniteOrOutOfRangeGain() {
        for gain in [Double.nan, -0.1, 1.1, .infinity, -.infinity] {
            #expect(throws: AddonFailure.self) {
                _ = try AudioAppIntent(gain: gain, isMuted: false, outputUIDs: [])
            }
        }

        #expect(throws: Never.self) {
            _ = try AudioAppIntent(gain: 0, isMuted: false, outputUIDs: [])
            _ = try AudioAppIntent(gain: 1, isMuted: true, outputUIDs: [])
        }
    }

    @Test
    func intentRejectsDuplicateOrTooManyOutputs() {
        let nine = (0..<9).map { "uid-\($0)" }

        #expect(throws: AddonFailure.self) {
            _ = try AudioAppIntent(gain: 1, isMuted: false, outputUIDs: nine)
        }
        #expect(throws: AddonFailure.self) {
            _ = try AudioAppIntent(gain: 1, isMuted: false, outputUIDs: ["a", "a"])
        }
        #expect(throws: AddonFailure.self) {
            _ = try AudioAppIntent(gain: 1, isMuted: false, outputUIDs: [""])
        }
        #expect(throws: Never.self) {
            _ = try AudioAppIntent(gain: 1, isMuted: false, outputUIDs: Array(nine.prefix(8)))
        }
    }

    @Test
    func neutralIntentIsNeutral() throws {
        #expect(AudioAppIntent.neutral.isNeutral)
        #expect(AudioAppIntent.neutral.gain == 1)
        #expect(!(try AudioAppIntent(gain: 0.5, isMuted: false, outputUIDs: [])).isNeutral)
        #expect(!(try AudioAppIntent(gain: 1, isMuted: true, outputUIDs: [])).isNeutral)
        #expect(!(try AudioAppIntent(gain: 1, isMuted: false, outputUIDs: ["a"])).isNeutral)
    }

    @Test
    func identityRejectsEmptyOrOversizedBundleID() {
        #expect(throws: AddonFailure.self) { _ = try AudioAppIdentity(bundleID: "") }
        #expect(throws: AddonFailure.self) {
            _ = try AudioAppIdentity(bundleID: String(repeating: "a", count: 256))
        }
    }

    @Test
    func wireRejectsOversizedAndUnknownFields() throws {
        let oversized = Data(repeating: 0x20, count: AudioHostWire.maximumBytes + 1)
        #expect(throws: AddonFailure.self) {
            _ = try AudioHostWire.decode(AudioAppIntent.self, from: oversized)
        }

        let unknown = Data(#"{"gain":1,"isMuted":false,"outputUIDs":[],"x":1}"#.utf8)
        #expect(throws: AddonFailure.self) {
            _ = try AudioHostWire.decode(AudioAppIntent.self, from: unknown)
        }

        let known = Data(#"{"gain":0.5,"isMuted":true,"outputUIDs":["a"]}"#.utf8)
        let intent = try AudioHostWire.decode(AudioAppIntent.self, from: known)
        #expect(intent == (try AudioAppIntent(gain: 0.5, isMuted: true, outputUIDs: ["a"])))
    }

    @Test
    func wireRejectsAnIntentThatBreaksItsRulesOnDecode() {
        let loud = Data(#"{"gain":2,"isMuted":false,"outputUIDs":[]}"#.utf8)

        #expect(throws: AddonFailure.self) {
            _ = try AudioHostWire.decode(AudioAppIntent.self, from: loud)
        }
    }

    @Test
    func commandsRoundTrip() throws {
        let safari = try identity()
        let music  = try identity("com.apple.Music")
        let muted  = try AudioAppIntent(gain: 0.25, isMuted: true, outputUIDs: ["speakers"])

        let commands: [AudioHostCommand] = [
            .replaceIntents([safari: muted, music: .neutral]),
            .replaceIntents([:]),
            .setIntent(safari, muted),
            .returnToNative(music),
        ]

        for command in commands {
            let data = try AudioHostWire.encode(command)
            #expect(try AudioHostWire.decode(AudioHostCommand.self, from: data) == command)
        }
    }

    @Test
    func commandRejectsUnknownFieldsAndRepeatedApps() {
        let unknown = Data(#"{"kind":"returnToNative","identity":{"bundleID":"a"},"x":1}"#.utf8)
        #expect(throws: AddonFailure.self) {
            _ = try AudioHostWire.decode(AudioHostCommand.self, from: unknown)
        }

        let entry    = #"{"identity":{"bundleID":"a"},"intent":{"gain":1,"isMuted":false,"outputUIDs":[]}}"#
        let repeated = Data(#"{"kind":"replaceIntents","intents":[\#(entry),\#(entry)]}"#.utf8)
        #expect(throws: AddonFailure.self) {
            _ = try AudioHostWire.decode(AudioHostCommand.self, from: repeated)
        }
    }

    @Test
    func snapshotRoundTripsWithUnknownCapture() throws {
        let app = try AudioAppSnapshot(
            identity           : identity(),
            displayName        : "Safari",
            intent             : .neutral,
            enforcement        : .native,
            effectiveOutputUIDs: ["speakers"]
        )

        for captureAllowed in [nil, true, false] as [Bool?] {
            let snapshot = try AudioHostSnapshot(generation: 7, apps: [app], captureAllowed: captureAllowed)
            let data     = try AudioHostWire.encode(snapshot)

            #expect(try AudioHostWire.decode(AudioHostSnapshot.self, from: data) == snapshot)
        }
    }

    @Test
    func snapshotCapsAppsAt64() throws {
        func app(_ index: Int) throws -> AudioAppSnapshot {
            try AudioAppSnapshot(
                identity           : identity("com.example.app\(index)"),
                displayName        : "App \(index)",
                intent             : .neutral,
                enforcement        : .native,
                effectiveOutputUIDs: []
            )
        }

        let sixtyFour = try (0..<64).map(app)
        #expect(throws: Never.self) {
            _ = try AudioHostSnapshot(generation: 1, apps: sixtyFour, captureAllowed: nil)
        }

        let sixtyFive = try (0..<65).map(app)
        #expect(throws: AddonFailure.self) {
            _ = try AudioHostSnapshot(generation: 1, apps: sixtyFive, captureAllowed: nil)
        }

        let repeated = [sixtyFour[0], sixtyFour[0]]
        #expect(throws: AddonFailure.self) {
            _ = try AudioHostSnapshot(generation: 1, apps: repeated, captureAllowed: nil)
        }
    }
}
