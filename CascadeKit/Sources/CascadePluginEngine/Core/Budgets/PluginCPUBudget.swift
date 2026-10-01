//
//  PluginCPUBudget.swift
//  CascadeKit
//

/// PluginCPUBudget is a plugin's CPU allowance, harvested from `AddonCPUBudget`: a bucket of
/// 100 ms that refills at 1/200 of elapsed time, so a plugin may spend a burst at once and half
/// a percent of one core for as long as it likes. Overspending leaves debt, which the plugin
/// repays by resting rather than being forgiven.
struct PluginCPUBudget: Sendable {

    static let capacity      = Duration.milliseconds(100)
    static let refillDivisor = 200

    private var balance        = Self.capacity
    private var lastObservation: Duration

    init(at instant: Duration) {
        lastObservation = instant
    }

    /// charge credits the time elapsed since the last charge, debits `cpuTime`, and returns how
    /// long the plugin must rest to be out of debt, zero when it is not in debt.
    mutating func charge(
        _ cpuTime : Duration,
        at instant: Duration
    ) -> Duration {
        let elapsed     = max(.zero, instant - lastObservation)
        balance         = min(Self.capacity, balance + elapsed / Self.refillDivisor) - cpuTime
        lastObservation = max(lastObservation, instant)

        return balance < .zero ? (.zero - balance) * Self.refillDivisor : .zero
    }
}
