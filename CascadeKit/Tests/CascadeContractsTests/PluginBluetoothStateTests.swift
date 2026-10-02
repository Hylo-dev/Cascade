//
//  PluginBluetoothStateTests.swift
//  CascadeKit
//

import Foundation
import Testing

@testable import CascadeContracts

@Suite
struct PluginBluetoothStateTests {

    private let airPods = PluginBluetoothState(
        deviceID   : "AA-BB-CC-DD-EE-FF",
        name       : "AirPods Pro",
        symbolName : "airpodspro",
        isConnected: true,
        battery    : PluginBluetoothBattery(level: 68, left: 72, right: 68, caseLevel: 81),
        model      : .airPodsPro,
        productID  : 0x200E,
        colorID    : 19,
        eventID    : 7,
        revision   : 2,
        kind       : .audioRoute,
        isAvailable: true
    )

    @Test
    func aStateRoundTripsThroughItsEvent() throws {
        let sparse = PluginBluetoothState(
            deviceID   : "11-22-33-44-55-66",
            name       : "Keyboard",
            symbolName : "keyboard",
            isConnected: false,
            battery    : nil,
            model      : .generic,
            productID  : nil,
            colorID    : nil,
            eventID    : 3,
            revision   : 0,
            kind       : .connection,
            isAvailable: true
        )

        #expect(PluginBluetoothState(try airPods.event()) == airPods)
        #expect(PluginBluetoothState(try sparse.event()) == sparse)
        #expect(try sparse.event().fields["productID"] == nil)
        #expect(try sparse.event().fields["batteryLevel"] == nil)
    }

    @Test
    func aBaselineIsEventZeroAndSaysWhetherMonitoringWorks() throws {
        let unavailable = PluginBluetoothState.baseline(isAvailable: false)

        #expect(unavailable.eventID == 0)
        #expect(!unavailable.isAvailable)
        #expect(PluginBluetoothState(try unavailable.event()) == unavailable)
        #expect(!unavailable.isNewConnection)
    }

    @Test
    func onlyTheFirstRevisionOfAConnectionIsANewConnection() {
        let connected = PluginBluetoothState(
            deviceID   : "AA-BB-CC-DD-EE-FF",
            name       : "AirPods",
            symbolName : "airpods",
            isConnected: true,
            battery    : nil,
            model      : .airPods,
            productID  : nil,
            colorID    : nil,
            eventID    : 4,
            revision   : 0,
            kind       : .connection,
            isAvailable: true
        )

        #expect(connected.isNewConnection)
        #expect(!airPods.isNewConnection)
    }

    @Test
    func anotherSourceOrAMalformedFieldIsNotABluetoothState() throws {
        var fields = try airPods.event().fields
        let power  = try PluginSourceEvent(source: "power", fields: fields)

        #expect(PluginBluetoothState(power) == nil)

        fields["model"] = .string("beats")
        #expect(PluginBluetoothState(try PluginSourceEvent(source: "bluetooth", fields: fields)) == nil)

        fields = try airPods.event().fields
        fields["eventID"] = .number(1.5)
        #expect(PluginBluetoothState(try PluginSourceEvent(source: "bluetooth", fields: fields)) == nil)

        fields["eventID"] = .number(-1)
        #expect(PluginBluetoothState(try PluginSourceEvent(source: "bluetooth", fields: fields)) == nil)

        fields = try airPods.event().fields
        fields["name"] = nil
        #expect(PluginBluetoothState(try PluginSourceEvent(source: "bluetooth", fields: fields)) == nil)
    }

    @Test
    func outOfRangeNumbersAreClampedOrDroppedNeverATrap() throws {
        var fields = try airPods.event().fields
        fields["batteryLevel"] = .number(1e300)
        fields["batteryLeft"]  = .number(-1e300)
        fields["productID"]    = .number(1e300)
        fields["colorID"]      = .number(-3)

        let state = try #require(PluginBluetoothState(try PluginSourceEvent(source: "bluetooth", fields: fields)))

        #expect(state.battery == PluginBluetoothBattery(level: 100, left: 0, right: 68, caseLevel: 81))
        #expect(state.productID == nil)
        #expect(state.colorID == nil)
        #expect(PluginBluetoothBattery(level: 140, left: nil, right: nil, caseLevel: -2) == PluginBluetoothBattery(level: 100, left: nil, right: nil, caseLevel: 0))
    }

    @Test
    func theConnectedDevicesRoundTripInTheirOrderAndAFifthIsLeftOut() throws {
        let devices = [
            PluginBluetoothDevice(name: "AirPods Pro", symbolName: "airpodspro", batteryLevel: 68),
            PluginBluetoothDevice(name: "Keyboard", symbolName: "keyboard", batteryLevel: nil),
            PluginBluetoothDevice(name: "Mouse", symbolName: "computermouse", batteryLevel: 140),
            PluginBluetoothDevice(name: "Speaker", symbolName: "speaker.wave.2", batteryLevel: 12),
            PluginBluetoothDevice(name: "Controller", symbolName: "gamecontroller", batteryLevel: 90),
        ]
        let three = PluginBluetoothState.baseline(isAvailable: true, connectedDevices: Array(devices.prefix(3)))
        let five  = PluginBluetoothState.baseline(isAvailable: true, connectedDevices: devices)
        let event = try three.event()

        #expect(PluginBluetoothState(event) == three)
        #expect(three.connectedDevices[2].batteryLevel == 100)
        #expect(event.fields["deviceCount"] == .number(3))
        #expect(event.fields["device1.name"] == .string("Keyboard"))
        #expect(event.fields["device1.battery"] == nil)
        #expect(five.connectedDevices == Array(devices.prefix(4)))
        #expect(PluginBluetoothState(try five.event()) == five)
    }

    @Test
    func aDeviceCountPastTheMaximumOrADeviceWithoutItsNameOrSymbolIsMalformed() throws {
        let state  = PluginBluetoothState.baseline(isAvailable: true, connectedDevices: [PluginBluetoothDevice(name: "Keyboard", symbolName: "keyboard", batteryLevel: 50)])
        var fields = try state.event().fields

        fields["deviceCount"] = .number(5)
        for index in 1..<5 {
            fields["device\(index).name"]   = .string("Keyboard")
            fields["device\(index).symbol"] = .string("keyboard")
        }
        #expect(PluginBluetoothState(try PluginSourceEvent(source: "bluetooth", fields: fields)) == nil)

        fields = try state.event().fields
        fields["device0.name"] = nil
        #expect(PluginBluetoothState(try PluginSourceEvent(source: "bluetooth", fields: fields)) == nil)

        fields = try state.event().fields
        fields["device0.symbol"] = nil
        #expect(PluginBluetoothState(try PluginSourceEvent(source: "bluetooth", fields: fields)) == nil)

        fields = try state.event().fields
        fields["deviceCount"] = .string("1")
        #expect(PluginBluetoothState(try PluginSourceEvent(source: "bluetooth", fields: fields)) == nil)
    }

    @Test
    func anEventWithoutADeviceCountListsNoDevices() throws {
        var fields = try airPods.event().fields
        fields["deviceCount"] = nil

        #expect(PluginBluetoothState(try PluginSourceEvent(source: "bluetooth", fields: fields)) == airPods)
        #expect(airPods.connectedDevices.isEmpty)
    }

    /// The longest names Bluetooth allows, 248 bytes, on the device of the event and on four
    /// connected devices, every number known, still fit one source event.
    @Test
    func fourDevicesWithTheLongestNamesFitOneSourceEvent() throws {
        let name   = String(repeating: "W", count: 248)
        let device = PluginBluetoothDevice(name: name, symbolName: "speaker.wave.2", batteryLevel: 100)
        let state  = PluginBluetoothState(
            deviceID        : "AA-BB-CC-DD-EE-FF",
            name            : name,
            symbolName      : "airpodspro",
            isConnected     : true,
            battery         : PluginBluetoothBattery(level: 100, left: 100, right: 100, caseLevel: 100),
            model           : .airPodsPro,
            productID       : 0x200E,
            colorID         : 19,
            eventID         : 9_007_199_254_740_991,
            revision        : 9_007_199_254_740_991,
            kind            : .audioRoute,
            isAvailable     : true,
            connectedDevices: Array(repeating: device, count: PluginBluetoothDevice.maximumCount)
        )
        let event  = try state.event()

        #expect(event.fields.count == 28)
        #expect(PluginBluetoothState(event) == state)
    }

    @Test
    func theDeviceAndItsBatteryAreCatalogComponentsAndTheRimCanStayNeutral() throws {
        #expect(PluginCatalog.components["bluetooth.device"] == 1)
        #expect(PluginCatalog.components["bluetooth.battery"] == 1)

        let neutral = try PluginNoticeAttributes(duration: 4, border: .neutral, compactWidth: 40, accessibilityLabel: "AirPods, Connected")
        #expect(try JSONDecoder().decode(PluginNoticeAttributes.self, from: JSONEncoder().encode(neutral)).border == .neutral)
    }
}
