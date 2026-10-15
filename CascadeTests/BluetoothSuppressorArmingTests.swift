//
//  BluetoothSuppressorArmingTests.swift
//  CascadeTests
//

import CascadeContracts
import Testing
@testable import Cascade

/// BluetoothSuppressorArmingTests feed the Bluetooth source's states to the decision that arms
/// the native banner's suppressor, as `CascadeServices` receives them.
struct BluetoothSuppressorArmingTests {

    /// connection is the state of event `eventID` for a pair of AirPods, at `revision`.
    private func connection(
        _ eventID: UInt64,
        revision : UInt64 = 0
    ) -> PluginBluetoothState {
        PluginBluetoothState(
            deviceID   : "AA-BB-CC-DD-EE-FF",
            name       : "AirPods",
            symbolName : "airpods",
            isConnected: true,
            battery    : nil,
            model      : .airPods,
            productID  : nil,
            colorID    : nil,
            eventID    : eventID,
            revision   : revision,
            kind       : .connection,
            isAvailable: true
        )
    }

    @Test
    func aConnectionArmsOnceHoweverOftenItsStateComesAgain() {
        var arming = BluetoothSuppressorArming()

        let armed = [
            connection(1),
            connection(1),
            connection(1, revision: 1),
            connection(2),
            connection(2),
        ].map { arming.arms(for: $0) }

        #expect(armed == [true, false, false, true, false], "A state sent again with a new list of devices is no new banner")
    }

    @Test
    func aBaselineStartsTheNumbersOver() {
        var arming = BluetoothSuppressorArming()

        let armed = [
            connection(3),
            .baseline(isAvailable: true),
            connection(1),
        ].map { arming.arms(for: $0) }

        #expect(armed == [true, false, true], "A restarted source numbers its events from one again")
    }
}
