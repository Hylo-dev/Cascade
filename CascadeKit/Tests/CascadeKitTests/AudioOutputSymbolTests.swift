//
//  AudioOutputSymbolTests.swift
//  CascadeKit
//

import CascadeContracts
import Testing
@testable import CascadeKit

struct AudioOutputSymbolTests {

    private func identity(_ model: PluginBluetoothDeviceModel) -> AudioBluetoothIdentity {
        AudioBluetoothIdentity(
            model    : model,
            productID: nil,
            colorID  : nil
        )
    }

    @Test
    func eachBluetoothModelHasItsOwnSymbol() {
        #expect(AudioOutputIcon.symbolName(for: identity(.airPods)) == "airpods")
        #expect(AudioOutputIcon.symbolName(for: identity(.airPodsPro)) == "airpods.pro")
        #expect(AudioOutputIcon.symbolName(for: identity(.airPodsMax)) == "airpods.max")
        #expect(AudioOutputIcon.symbolName(for: identity(.generic)) == "headphones")
    }

    @Test
    func theNewerDottedNamesFallBackToTheOlderOnes() {
        #expect(AudioOutputSymbol.fallback(for: "airpods.pro") == "airpodspro")
        #expect(AudioOutputSymbol.fallback(for: "airpods.max") == "airpodsmax")
        #expect(AudioOutputSymbol.fallback(for: "macbook") == "laptopcomputer")
        #expect(AudioOutputSymbol.fallback(for: "airpods") == nil)
        #expect(AudioOutputSymbol.fallback(for: "headphones") == nil)
    }

    @Test
    func thePreferredNameWinsWhenTheSystemHasIt() {
        let name = AudioOutputSymbol.resolve("airpods.pro") { _ in true }

        #expect(name == "airpods.pro")
    }

    @Test
    func theFallbackIsUsedWhenOnlyItExists() {
        let name = AudioOutputSymbol.resolve("airpods.max") { $0 == "airpodsmax" }

        #expect(name == "airpodsmax")
    }

    @Test
    func withNeitherNameTheOriginalIsKeptSoSwiftUIDrawsNothingRatherThanTheWrongThing() {
        let name = AudioOutputSymbol.resolve("airpods.pro") { _ in false }

        #expect(name == "airpods.pro")
    }

    @Test
    func theInstalledAnswerIsStableAcrossCalls() {
        let first  = AudioOutputSymbol.installedName(for: "speaker.fill")
        let second = AudioOutputSymbol.installedName(for: "speaker.fill")

        #expect(first == "speaker.fill")
        #expect(second == first)
    }
}
