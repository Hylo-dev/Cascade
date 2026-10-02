//
//  PluginNetworkStateTests.swift
//  CascadeKit
//

import Testing

@testable import CascadeContracts

@Suite
struct PluginNetworkStateTests {

    @Test
    func aStateRoundTripsThroughItsEvent() throws {
        let wifi    = PluginNetworkState(isConnected: true, interface: .wifi, isExpensive: false, isConstrained: true)
        let offline = PluginNetworkState(isConnected: false, interface: .none, isExpensive: false, isConstrained: false)

        #expect(PluginNetworkState(try wifi.event()) == wifi)
        #expect(PluginNetworkState(try offline.event()) == offline)
        #expect(try wifi.event().fields == [
            "isConnected"  : .bool(true),
            "interface"    : .string("wifi"),
            "isExpensive"  : .bool(false),
            "isConstrained": .bool(true),
        ])
    }

    @Test
    func anotherSourceOrAMalformedInterfaceIsNotANetworkState() throws {
        let fields: [String: PluginValue] = [
            "isConnected"  : .bool(true),
            "interface"    : .string("wifi"),
            "isExpensive"  : .bool(false),
            "isConstrained": .bool(false),
        ]
        var bluetooth = fields
        bluetooth["interface"] = .string("bluetooth")
        var missing = fields
        missing["isConstrained"] = nil

        #expect(PluginNetworkState(try PluginSourceEvent(source: "power", fields: fields)) == nil)
        #expect(PluginNetworkState(try PluginSourceEvent(source: "network", fields: bluetooth)) == nil)
        #expect(PluginNetworkState(try PluginSourceEvent(source: "network", fields: missing)) == nil)
    }
}
