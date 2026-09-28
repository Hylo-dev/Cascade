//
//  SystemMacPowerReader.swift
//  Cascade
//

import Foundation
import IOKit.ps

/// SystemMacPowerReader copies the IOKit snapshot on a utility queue. No CF
/// object escapes its owning snapshot and no battery or accessory lookup runs
/// inside a view.
nonisolated struct SystemMacPowerReader: MacPowerReading {

    func read() -> MacPowerSnapshot? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else {
            return nil
        }

        for source in sources {
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue()
                as? [String: Any]
            else { continue }

            if let snapshot = Self.snapshot(
                from          : values,
                isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled
            ) {
                return snapshot
            }
        }

        return nil
    }

    static func snapshot(
        from values   : [String: Any],
        isLowPowerMode: Bool
    ) -> MacPowerSnapshot? {
        guard values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              values[kIOPSIsPresentKey] as? Bool != false,
              let source = values[kIOPSPowerSourceStateKey] as? String,
              source == kIOPSACPowerValue || source == kIOPSBatteryPowerValue
        else { return nil }

        let percentage: Int?
        if let current = values[kIOPSCurrentCapacityKey] as? Int,
           let maximum = values[kIOPSMaxCapacityKey] as? Int,
           current >= 0, maximum > 0 {
            percentage = Int((min(1, Double(current) / Double(maximum)) * 100).rounded())
        } else {
            percentage = nil
        }

        return MacPowerSnapshot(
            percentage     : percentage,
            isExternalPower: source == kIOPSACPowerValue,
            isCharging     : values[kIOPSIsChargingKey] as? Bool ?? false,
            isLowPowerMode : isLowPowerMode
        )
    }
}
