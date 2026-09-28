//
//  ProcessMetrics.swift
//  CascadeKit
//

import Foundation

/// ProcessMetricBinding is an explicitly supplied observational expectation, scoped to one host
/// binding and clock domain. Birth ticks and executable UUID do not authenticate a publisher,
/// identify every exec generation, or grant any process-control authority.
struct ProcessMetricBinding: Equatable, Sendable {
    let pid: Int32
    let birthAbsoluteTicks: UInt64
    let executableUUID: UUID
    let token: UUID
    let clockDomain: UUID

    var isValid: Bool {
        pid > 0 && birthAbsoluteTicks > 0 && executableUUID != Self.zeroUUID
    }

    static let zeroUUID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
}

struct ProcessMetricTimebase: Equatable, Sendable {
    let numer: UInt32
    let denom: UInt32

    var isValid: Bool { numer > 0 && denom > 0 }
}

/// ProcessMetricWindow brackets a read's acquisition uncertainty between two uptime ticks; it is not
/// an atomic timestamp. Raw birth ticks and these ticks share the native Mach absolute clock domain.
struct ProcessMetricWindow: Equatable, Sendable {
    let startTicks: UInt64
    let endTicks: UInt64

    func isValid(for binding: ProcessMetricBinding) -> Bool {
        startTicks >= binding.birthAbsoluteTicks && endTicks >= startTicks
    }
}

/// ProcessMetricRecord holds values extracted only from a successful public v0 read. CPU fields
/// are Mach ticks; footprint is bytes. A failed read cannot carry a record of apparent zeros.
struct ProcessMetricRecord: Equatable, Sendable {
    let birthAbsoluteTicks: UInt64
    let executableUUID: UUID
    let userTicks: UInt64
    let systemTicks: UInt64
    let footprintBytes: UInt64
    let exitAbsoluteTicks: UInt64
}

enum RawProcessMetricRead: Equatable, Sendable {
    case success(ProcessMetricRecord)
    case failure(Int32)
}

enum RawProcessMetricTimebase: Equatable, Sendable {
    case success(ProcessMetricTimebase)
    case failure(Int32)
}

struct ProcessMetricObservation: Equatable, Sendable {
    let binding: ProcessMetricBinding
    let userTicks: UInt64
    let systemTicks: UInt64
    let footprintBytes: UInt64
    let window: ProcessMetricWindow
    let timebase: ProcessMetricTimebase
}

enum ProcessMetricFailure: Equatable, Sendable {
    case invalidExpectation, identityUnavailable, identityMismatch, exited
    case readFailed(Int32), timebaseFailed(Int32)
    case invalidAcquisition, invalidTimebase
    case bindingInvalidated, bindingMismatch, timebaseChanged, nonIncreasingTime
    case counterRegression, counterOverflow, conversionOverflow, zeroElapsed
}

enum ProcessMetricReadResult: Equatable, Sendable {
    case sample(ProcessMetricObservation)
    case unavailable(ProcessMetricFailure)
}

struct ProcessCPUInterval: Equatable, Sendable {
    let cpuNanoseconds: UInt64
    let elapsedNanoseconds: UInt64
    let previousWindow: ProcessMetricWindow
    let currentWindow: ProcessMetricWindow
}

enum ProcessMetricReductionStatus: Equatable, Sendable {
    case baseline, interval
    case reset(ProcessMetricFailure), unavailable(ProcessMetricFailure), invalid(ProcessMetricFailure)
}

/// ProcessMetricReduction is the outcome of one reduction; a current valid footprint can survive
/// CPU-only arithmetic failure. Neither a baseline nor an unavailable/reset interval represents
/// measured zero CPU use.
struct ProcessMetricReduction: Equatable, Sendable {
    let status: ProcessMetricReductionStatus
    let footprintBytes: UInt64?
    let interval: ProcessCPUInterval?
}

/// ProcessMetricsReducer is a fixed-state, purely synchronous reducer. Its owner explicitly supplies
/// resets; this value installs no observers, timers, tasks, or process lifecycle operations.
struct ProcessMetricsReducer: Sendable {
    let binding: ProcessMetricBinding
    private var baseline: ProcessMetricObservation?
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
                status: .unavailable(.bindingInvalidated), footprintBytes: nil, interval: nil
            )
        }

        switch result {
        case .unavailable(let failure):
            baseline = nil
            if failure == .identityMismatch || failure == .exited {
                isInvalidated = true
            }
            return ProcessMetricReduction(status: .unavailable(failure), footprintBytes: nil, interval: nil)

        case .sample(let current):
            guard current.binding == binding else { return reject(.bindingMismatch) }
            guard current.window.isValid(for: binding) else { return reject(.invalidAcquisition) }
            guard current.timebase.isValid else { return reject(.invalidTimebase) }

            guard let previous = baseline else {
                baseline = current
                return ProcessMetricReduction(status: .baseline, footprintBytes: current.footprintBytes, interval: nil)
            }
            guard current.timebase == previous.timebase else {
                return reject(.timebaseChanged, footprint: current.footprintBytes)
            }
            guard current.window.startTicks >= previous.window.endTicks,
                  current.window.endTicks > previous.window.endTicks else {
                return reject(.nonIncreasingTime, footprint: current.footprintBytes)
            }
            guard current.userTicks >= previous.userTicks,
                  current.systemTicks >= previous.systemTicks else {
                baseline = current
                return ProcessMetricReduction(
                    status: .reset(.counterRegression), footprintBytes: current.footprintBytes, interval: nil
                )
            }

            // Subtract components first: cumulative user+system can overflow even
            // when the interval's small component deltas are both representable.
            let userDelta = current.userTicks - previous.userTicks
            let systemDelta = current.systemTicks - previous.systemTicks
            let (cpuTicks, overflow) = userDelta.addingReportingOverflow(systemDelta)
            guard !overflow else { return reject(.counterOverflow, footprint: current.footprintBytes) }

            let elapsedTicks = current.window.endTicks - previous.window.endTicks
            guard let cpu = nanoseconds(cpuTicks, timebase: current.timebase),
                  let elapsed = nanoseconds(elapsedTicks, timebase: current.timebase) else {
                return reject(.conversionOverflow, footprint: current.footprintBytes)
            }
            guard elapsed > 0 else { return reject(.zeroElapsed, footprint: current.footprintBytes) }

            let interval = ProcessCPUInterval(
                cpuNanoseconds: cpu,
                elapsedNanoseconds: elapsed,
                previousWindow: previous.window,
                currentWindow: current.window
            )
            baseline = current
            return ProcessMetricReduction(status: .interval, footprintBytes: current.footprintBytes, interval: interval)
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
        return ProcessMetricReduction(status: .invalid(failure), footprintBytes: footprint, interval: nil)
    }

    /// nanoseconds converts a tick delta through the Mach timebase, rounding only once, after CPU tick
    /// deltas are combined. Full-width multiplication admits representable quotients even when the
    /// intermediate product exceeds UInt64. dividingFullWidth traps for zero divisors/unrepresentable
    /// quotients, so validate both before invoking it; no wrapping or saturating arithmetic.
    private func nanoseconds(_ ticks: UInt64, timebase: ProcessMetricTimebase) -> UInt64? {
        guard timebase.isValid else { return nil }
        let divisor = UInt64(timebase.denom)
        let product = ticks.multipliedFullWidth(by: UInt64(timebase.numer))
        guard product.high < divisor else { return nil }
        return divisor.dividingFullWidth(product).quotient
    }
}
