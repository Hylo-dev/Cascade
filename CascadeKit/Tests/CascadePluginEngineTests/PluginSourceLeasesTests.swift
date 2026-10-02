//
//  PluginSourceLeasesTests.swift
//  CascadeKit
//

import CascadeContracts
import Testing

@testable import CascadePluginEngine

@Suite
struct PluginSourceLeasesTests {

    private let music = PluginEngineFixtures.musicID
    private let radio = PluginEngineFixtures.radioID

    @Test
    func aSourceStartsWithItsFirstHolderAndStopsWithItsLast() {
        var leases  = PluginSourceLeases()
        let started = leases.lease("power", for: music)
        let joined  = leases.lease("power", for: radio)
        let left    = leases.release("power", for: music)
        let stopped = leases.release("power", for: radio)

        #expect(started)
        #expect(!joined)
        #expect(!left)
        #expect(stopped)
    }

    @Test
    func releasingAPluginThatHoldsNothingChangesNothing() {
        var leases = PluginSourceLeases()
        _ = leases.lease("power", for: music)

        let stranger = leases.release("power", for: radio)
        let holder   = leases.release("power", for: music)

        #expect(!stranger)
        #expect(holder)
    }

    @Test
    func anEventReachesTheHoldersAndBecomesTheLatestState() throws {
        let charging = try PluginEngineFixtures.power(charging: true)
        var leases   = PluginSourceLeases()
        _ = leases.lease("power", for: music)

        #expect(leases.record(charging) == [music])
        #expect(leases.latest(of: ["power"]) == [charging])
    }

    @Test
    func aSourceNobodyHoldsDropsItsEvents() throws {
        var leases = PluginSourceLeases()

        #expect(leases.record(try PluginEngineFixtures.power(charging: true)).isEmpty)
        #expect(leases.latest(of: ["power"]).isEmpty)
    }

    @Test
    func aStoppedSourceForgetsItsState() throws {
        var leases = PluginSourceLeases()
        _ = leases.lease("power", for: music)
        _ = leases.record(try PluginEngineFixtures.power(charging: true))
        _ = leases.release("power", for: music)
        _ = leases.lease("power", for: music)

        #expect(leases.latest(of: ["power"]).isEmpty)
    }
}
