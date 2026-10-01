//
//  PluginVolumeStateTests.swift
//  CascadeKit
//

import Testing

@testable import CascadeContracts

@Suite
struct PluginVolumeStateTests {

    @Test
    func aStateRoundTripsThroughItsEvent() throws {
        let level    = PluginVolumeState(percentage: 65, isMuted: false, announcement: 3)
        let baseline = PluginVolumeState(percentage: nil, isMuted: false, announcement: 0)

        #expect(PluginVolumeState(try level.event()) == level)
        #expect(PluginVolumeState(try baseline.event()) == baseline)
        #expect(try baseline.event().fields["percentage"] == nil)
    }

    @Test
    func anotherSourceOrAMissingFieldIsNotAVolumeState() throws {
        let power   = try PluginSourceEvent(source: "power", fields: ["isMuted": .bool(false), "announcement": .number(1)])
        let partial = try PluginSourceEvent(source: "volume", fields: ["isMuted": .bool(false)])

        #expect(PluginVolumeState(power) == nil)
        #expect(PluginVolumeState(partial) == nil)
    }

    @Test
    func theLevelStaysWithinTheScaleAndTheBarIsACatalogComponent() {
        #expect(PluginVolumeState(percentage: 140, isMuted: false, announcement: 1).percentage == 100)
        #expect(PluginCatalog.components["volume.level"] == 1)
    }
}
