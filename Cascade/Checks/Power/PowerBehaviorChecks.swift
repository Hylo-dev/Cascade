//
//  PowerBehaviorChecks.swift
//  Cascade
//

#if POWER_MONITOR_TESTS
import Foundation
import IOKit.ps

@main
private enum PowerBehaviorChecks {
    static func main() throws {
        var reducer = PowerConnectionReducer()
        let battery = MacPowerSnapshot(percentage: 19, isExternalPower: false, isCharging: false, isLowPowerMode: false)
        let charging = MacPowerSnapshot(percentage: 19, isExternalPower: true, isCharging: true, isLowPowerMode: false)
        try expect(reducer.receive(battery) == nil, "Startup must establish a silent baseline")
        guard case .connected(let first, let revision) = reducer.receive(charging) else {
            throw CheckFailure.failed("Connecting the charger must show a notice")
        }
        try expect(first == charging, "A connection must preserve the actual battery and energy mode")
        try expect(reducer.receive(charging) == nil, "Duplicate callbacks must not replay the notice")
        let lowPower = MacPowerSnapshot(percentage: 20, isExternalPower: true, isCharging: true, isLowPowerMode: true)
        guard case .updated(let changed, let nextRevision) = reducer.receive(lowPower) else {
            throw CheckFailure.failed("Battery and energy mode changes must update the existing notice")
        }
        try expect(changed == lowPower && nextRevision > revision, "Updated content needs a newer revision")
        try expect(reducer.receive(nil) == nil, "An unavailable sample must not invent a disconnection")
        try expect(reducer.receive(lowPower) == nil, "Recovery after an unavailable sample must not replay")
        try expect(reducer.receive(battery) == .disconnected, "Unplugging must dismiss the charging notice")
        let held = MacPowerSnapshot(percentage: 80, isExternalPower: true, isCharging: false, isLowPowerMode: false)
        guard case .connected(let connected, _) = reducer.receive(held) else {
            throw CheckFailure.failed("Optimized charging must still announce an attached charger")
        }
        try expect(connected == held, "Charging on hold must remain distinguishable from active charging")
        var restarted = PowerConnectionReducer()
        try expect(restarted.receive(charging) == nil, "Launching while already plugged in must stay silent")
        try expect(restarted.receive(charging) == nil, "A startup callback must also stay silent")
        try checkBatteryParsing()
        print("Power connection behavior checks passed")
    }

    private static func checkBatteryParsing() throws {
        var values: [String: Any] = [
            kIOPSTypeKey: kIOPSInternalBatteryType,
            kIOPSIsPresentKey: true,
            kIOPSPowerSourceStateKey: kIOPSACPowerValue,
            kIOPSCurrentCapacityKey: 38,
            kIOPSMaxCapacityKey: 200,
            kIOPSIsChargingKey: false
        ]
        let sample = SystemMacPowerReader.snapshot(from: values, isLowPowerMode: true)
        try expect(sample?.percentage == 19, "Capacity must be normalized to the reported maximum")
        try expect(sample?.isExternalPower == true && sample?.isCharging == false, "Charging on hold is still plugged in")
        try expect(sample?.isLowPowerMode == true, "Energy mode must come from the system, not the battery percentage")
        values[kIOPSMaxCapacityKey] = 0
        try expect(SystemMacPowerReader.snapshot(from: values, isLowPowerMode: false)?.percentage == nil, "Unknown capacity must not be displayed as zero")
        values[kIOPSMaxCapacityKey] = 100
        values[kIOPSCurrentCapacityKey] = 150
        try expect(SystemMacPowerReader.snapshot(from: values, isLowPowerMode: false)?.percentage == 100, "Over-range capacity must stay within the icon bounds")
        values[kIOPSCurrentCapacityKey] = -1
        try expect(SystemMacPowerReader.snapshot(from: values, isLowPowerMode: false)?.percentage == nil, "Invalid negative capacity is unknown")
        values[kIOPSIsPresentKey] = false
        try expect(SystemMacPowerReader.snapshot(from: values, isLowPowerMode: false) == nil, "Missing built-in battery must not produce a Mac notice")
        values[kIOPSIsPresentKey] = true
        values[kIOPSTypeKey] = "UPS"
        try expect(SystemMacPowerReader.snapshot(from: values, isLowPowerMode: false) == nil, "A UPS must not masquerade as the Mac battery")
    }

    private enum CheckFailure: Error { case failed(String) }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        guard condition() else { throw CheckFailure.failed(message) }
    }
}

#endif
