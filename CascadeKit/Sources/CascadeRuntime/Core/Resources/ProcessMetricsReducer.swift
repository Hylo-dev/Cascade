//
//  ProcessMetricsReducer.swift
//  CascadeKit
//

import Foundation

/// ProcessMetricsReducer is a fixed-state, purely synchronous reducer. Its owner explicitly supplies
/// resets; this value installs no observers, timers, tasks, or process lifecycle operations.
struct ProcessMetricsReducer: Sendable {

    let binding: ProcessMetricBinding

    private var baseline     : ProcessMetricObservation?
    private var isInvalidated = false

    init(binding: ProcessMetricBinding) {
        self.binding = binding
    }

    mutating func consume(_ result: ProcessMetricReadResult) -> ProcessMetricReduction {
        guard binding.isValid else {
            return reject(.invalidExpectation)
        }
        guard !isInvalidated else {
            return ProcessMetricReduction(
                status        : .unavailable(.bindingInvalidated),
                footprintBytes: nil,
                interval      : nil
            )
        }

        switch result {
            case .unavailable(let failure):
                baseline = nil
                if failure == .identityMismatch || failure == .exited {
                    isInvalidated = true
                }
                return ProcessMetricReduction(
                    status        : .unavailable(failure),
                    footprintBytes: nil,
                    interval      : nil
                )

            case .sample(let current):
                guard current.binding == binding else { return reject(.bindingMismatch) }
                guard current.window.isValid(for: binding) else { return reject(.invalidAcquisition) }
                guard current.timebase.isValid else { return reject(.invalidTimebase) }

                guard let previous = baseline else {
                    baseline = current
                    return ProcessMetricReduction(
                        status        : .baseline,
                        footprintBytes: current.footprintBytes,
                        interval      : nil
                    )
                }
                guard current.timebase == previous.timebase else {
                    return reject(.timebaseChanged, footprint: current.footprintBytes)
                }
                guard current.window.startTicks >= previous.window.endTicks,
                      current.window.endTicks > previous.window.endTicks
                else {
                    return reject(.nonIncreasingTime, footprint: current.footprintBytes)
                }
                guard current.userTicks >= previous.userTicks,
                      current.systemTicks >= previous.systemTicks
                else {
                    baseline = current
                    return ProcessMetricReduction(
                        status        : .reset(.counterRegression),
                        footprintBytes: current.footprintBytes,
                        interval      : nil
                    )
                }

                // Subtract components first: cumulative user+system can overflow even
                // when the interval's small component deltas are both representable.
                let userDelta   = current.userTicks - previous.userTicks
                let systemDelta = current.systemTicks - previous.systemTicks
                let (cpuTicks, overflow) = userDelta.addingReportingOverflow(systemDelta)
                guard !overflow else { return reject(.counterOverflow, footprint: current.footprintBytes) }

                let elapsedTicks = current.window.endTicks - previous.window.endTicks
                guard let cpu = nanoseconds(cpuTicks, timebase: current.timebase),
                      let elapsed = nanoseconds(elapsedTicks, timebase: current.timebase)
                else {
                    return reject(.conversionOverflow, footprint: current.footprintBytes)
                }
                guard elapsed > 0 else { return reject(.zeroElapsed, footprint: current.footprintBytes) }

                let interval = ProcessCPUInterval(
                    cpuNanoseconds    : cpu,
                    elapsedNanoseconds: elapsed,
                    previousWindow    : previous.window,
                    currentWindow     : current.window
                )
                baseline = current
                return ProcessMetricReduction(
                    status        : .interval,
                    footprintBytes: current.footprintBytes,
                    interval      : interval
                )
        }
    }

    /// reset breaks continuity for a future owner-controlled lifecycle/wake event.
    /// It cannot revive a rejected identity; that requires a new reducer binding.
    mutating func reset() {
        baseline = nil
    }

    private mutating func reject(
        _ failure: ProcessMetricFailure,
        footprint: UInt64? = nil
    ) -> ProcessMetricReduction {
        baseline = nil
        return ProcessMetricReduction(
            status        : .invalid(failure),
            footprintBytes: footprint,
            interval      : nil
        )
    }

    /// nanoseconds converts a tick delta through the Mach timebase, rounding only once, after CPU tick
    /// deltas are combined. Full-width multiplication admits representable quotients even when the
    /// intermediate product exceeds UInt64. dividingFullWidth traps for zero divisors/unrepresentable
    /// quotients, so validate both before invoking it; no wrapping or saturating arithmetic.
    private func nanoseconds(
        _ ticks : UInt64,
        timebase: ProcessMetricTimebase
    ) -> UInt64? {
        guard timebase.isValid else { return nil }

        let divisor = UInt64(timebase.denom)
        let product = ticks.multipliedFullWidth(by: UInt64(timebase.numer))
        guard product.high < divisor else { return nil }

        return divisor.dividingFullWidth(product).quotient
    }
}
