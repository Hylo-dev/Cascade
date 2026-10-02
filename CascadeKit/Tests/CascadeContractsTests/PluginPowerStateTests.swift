//
//  PluginPowerStateTests.swift
//  CascadeKit
//

import Testing

@testable import CascadeContracts

@Suite
struct PluginPowerStateTests {

    @Test
    func aStateRoundTripsThroughItsEvent() throws {
        let known   = PluginPowerState(percentage: 19, isExternalPower: true, isCharging: true, isLowPowerMode: false)
        let unknown = PluginPowerState(percentage: nil, isExternalPower: false, isCharging: false, isLowPowerMode: true)

        #expect(PluginPowerState(try known.event()) == known)
        #expect(PluginPowerState(try unknown.event()) == unknown)
        #expect(try unknown.event().fields["percentage"] == nil)
    }

    @Test
    func anotherSourceOrAMissingFieldIsNotAPowerState() throws {
        let volume  = try PluginSourceEvent(source: "volume", fields: ["isExternalPower": .bool(true), "isCharging": .bool(true), "isLowPowerMode": .bool(false)])
        let partial = try PluginSourceEvent(source: "power", fields: ["isExternalPower": .bool(true)])

        #expect(PluginPowerState(volume) == nil)
        #expect(PluginPowerState(partial) == nil)
    }

    @Test
    func thePercentageStaysWithinTheBattery() {
        #expect(PluginPowerState(percentage: 150, isExternalPower: true, isCharging: false, isLowPowerMode: false).percentage == 100)
        #expect(PluginPowerState(percentage: -3, isExternalPower: true, isCharging: false, isLowPowerMode: false).percentage == 0)
    }

    @Test
    func theBatteryIsACatalogComponent() {
        #expect(PluginCatalog.components["power.battery"] == 1)
    }

    @Test
    func anOutOfRangeChargeIsClampedNotATrap() throws {
        let huge = try PluginSourceEvent(source: "power", fields: ["percentage": .number(1e300), "isExternalPower": .bool(true), "isCharging": .bool(true), "isLowPowerMode": .bool(false)])

        #expect(PluginPowerState(huge)?.percentage == 100)
    }
}
