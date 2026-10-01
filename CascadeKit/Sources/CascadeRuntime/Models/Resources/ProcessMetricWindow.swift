//
//  ProcessMetricWindow.swift
//  CascadeKit
//

/// ProcessMetricWindow brackets a read's acquisition uncertainty between two uptime ticks; it is not
/// an atomic timestamp. Raw birth ticks and these ticks share the native Mach absolute clock domain.
struct ProcessMetricWindow: Equatable, Sendable {

    let startTicks: UInt64
    let endTicks  : UInt64

    func isValid(for binding: ProcessMetricBinding) -> Bool {
        startTicks >= binding.birthAbsoluteTicks && endTicks >= startTicks
    }
}
