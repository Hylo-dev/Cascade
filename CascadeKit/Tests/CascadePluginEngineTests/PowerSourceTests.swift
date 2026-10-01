//
//  PowerSourceTests.swift
//  CascadeKit
//

import CascadeContracts
import IOKit.ps
import Synchronization
import Testing

@testable import CascadePluginHost

@Suite
struct PowerSourceTests {

    private let battery: [String: Any] = [
        kIOPSTypeKey            : kIOPSInternalBatteryType,
        kIOPSIsPresentKey       : true,
        kIOPSPowerSourceStateKey: kIOPSACPowerValue,
        kIOPSCurrentCapacityKey : 38,
        kIOPSMaxCapacityKey     : 200,
        kIOPSIsChargingKey      : false,
    ]

    @Test
    func theBuiltInBatteryIsReadAsTheSystemReportsIt() {
        let state = PowerSource.state(from: battery, isLowPowerMode: true)

        #expect(state == PluginPowerState(percentage: 19, isExternalPower: true, isCharging: false, isLowPowerMode: true))
    }

    @Test
    func anUnknownOrOverRangeChargeIsNeverShownAsZeroOrPastFull() {
        var values = battery
        values[kIOPSMaxCapacityKey] = 0
        #expect(PowerSource.state(from: values, isLowPowerMode: false)?.percentage == nil)

        values[kIOPSMaxCapacityKey]     = 100
        values[kIOPSCurrentCapacityKey] = 150
        #expect(PowerSource.state(from: values, isLowPowerMode: false)?.percentage == 100)

        values[kIOPSCurrentCapacityKey] = -1
        #expect(PowerSource.state(from: values, isLowPowerMode: false)?.percentage == nil)
    }

    @Test
    func onlyThePresentBuiltInBatteryIsTheMacsPower() {
        var missing = battery
        missing[kIOPSIsPresentKey] = false
        var ups = battery
        ups[kIOPSTypeKey] = "UPS"

        #expect(PowerSource.state(from: missing, isLowPowerMode: false) == nil)
        #expect(PowerSource.state(from: ups, isLowPowerMode: false) == nil)
    }

    @Test
    func itEmitsTheCurrentStateOnceThenOnlyChanges() throws {
        let charging = PluginPowerState(percentage: 19, isExternalPower: true, isCharging: true, isLowPowerMode: false)
        let reading  = Mutex<PluginPowerState?>(charging)
        let source   = PowerSource { reading.withLock { $0 } }
        let emitted  = Mutex<[PluginSourceEvent]>([])
        source.start { event in emitted.withLock { $0.append(event) } }

        source.sample()
        reading.withLock { $0 = PluginPowerState(percentage: 20, isExternalPower: true, isCharging: true, isLowPowerMode: false) }
        source.sample()
        source.stop()
        reading.withLock { $0 = charging }
        source.sample()

        #expect(emitted.withLock { $0 }.compactMap(PluginPowerState.init).map(\.percentage) == [19, 20])
    }

    @Test
    func aMacWithoutABatteryEmitsNothing() {
        let source  = PowerSource { nil }
        let emitted = Mutex(0)
        source.start { _ in emitted.withLock { $0 += 1 } }

        source.sample()

        #expect(emitted.withLock { $0 } == 0)
    }

    @Test
    func theCatalogNamesWhatItBuilds() {
        #expect(Set(PluginHostCatalog.sources().keys) == PluginHostCatalog.names)
    }
}
