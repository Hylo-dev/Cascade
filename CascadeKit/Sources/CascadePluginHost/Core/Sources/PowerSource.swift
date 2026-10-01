//
//  PowerSource.swift
//  CascadeKit
//

import CascadeContracts
import Foundation
import IOKit.ps
import notify

/// PowerSource is the `power` catalog source: the built-in battery's state, read from IOKit when
/// the system says a power source changed or Low Power Mode toggled, and emitted only when it
/// differs from the last one. It waits on a notify(3) token and a notification observer, both
/// delivered to its own utility queue, so it needs no run loop and costs nothing between
/// changes. A Mac without a built-in battery never emits; an accessory battery or a UPS never
/// passes for one.
///
/// Every stored property below is read and written only on `queue`, which is what makes the type
/// safe to share; `start` and `stop` reach it with `queue.sync` from the XPC threads, never from
/// the queue itself.
public final class PowerSource: PluginCatalogSource, @unchecked Sendable {

    private let queue = DispatchQueue(label: "cascade.plugin-host.power", qos: .utility)
    private let read : @Sendable () -> PluginPowerState?

    private var token   : Int32?
    private var observer: (any NSObjectProtocol)?
    private var emit    : (@Sendable (PluginSourceEvent) -> Void)?
    private var last    : PluginPowerState?

    public init(read: @escaping @Sendable () -> PluginPowerState? = PowerSource.readSystem) {
        self.read = read
    }

    public func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void) {
        queue.sync {
            unregister()

            var token = NOTIFY_TOKEN_INVALID
            if notify_register_dispatch(kIOPSNotifyAnyPowerSource, &token, queue, { [weak self] _ in self?.emitIfChanged() }) == NOTIFY_STATUS_OK {
                self.token = token
            }
            observer = NotificationCenter.default.addObserver(
                forName: .NSProcessInfoPowerStateDidChange,
                object : nil,
                queue  : nil
            ) { [weak self] _ in
                guard let self else { return }

                queue.async { [weak self] in self?.emitIfChanged() }
            }
            self.emit = emit
            emitIfChanged()
        }
    }

    public func stop() {
        queue.sync {
            unregister()
        }
    }

    /// sample reads and emits at once, as a notification would; tests drive the source with it.
    func sample() {
        queue.sync {
            emitIfChanged()
        }
    }

    private func emitIfChanged() {
        guard let emit, let current = read(), current != last, let event = try? current.event() else { return }

        last = current
        emit(event)
    }

    private func unregister() {
        if let token {
            notify_cancel(token)
        }
        if let observer {
            NotificationCenter.default.removeObserver(observer)
        }
        token    = nil
        observer = nil
        emit     = nil
        last     = nil
    }

    /// readSystem reads the built-in battery from IOKit. No CF object outlives the call.
    public static func readSystem() -> PluginPowerState? {
        guard let info    = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let values = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any] else { continue }

            if let state = state(from: values, isLowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled) {
                return state
            }
        }

        return nil
    }

    /// state reads one power source's description: only a present, built-in battery on AC or
    /// battery power is the Mac's. A charge IOKit cannot measure is unknown, never zero.
    static func state(
        from values   : [String: Any],
        isLowPowerMode: Bool
    ) -> PluginPowerState? {
        guard values[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
              values[kIOPSIsPresentKey] as? Bool != false,
              let source = values[kIOPSPowerSourceStateKey] as? String,
              source == kIOPSACPowerValue || source == kIOPSBatteryPowerValue
        else { return nil }

        var percentage: Int?
        if let current = values[kIOPSCurrentCapacityKey] as? Int,
           let maximum = values[kIOPSMaxCapacityKey] as? Int,
           current >= 0, maximum > 0 {
            percentage = Int((min(1, Double(current) / Double(maximum)) * 100).rounded())
        }

        return PluginPowerState(
            percentage     : percentage,
            isExternalPower: source == kIOPSACPowerValue,
            isCharging     : values[kIOPSIsChargingKey] as? Bool ?? false,
            isLowPowerMode : isLowPowerMode
        )
    }
}
