//
//  PluginPublicationBudget.swift
//  CascadeKit
//

/// PluginPublicationBudget limits how often a plugin changes what is on screen: a burst of
/// eight publications, then one every 250 ms. A plugin past it is not refused; the kernel holds
/// its next event until a token is back, and the events that arrive meanwhile coalesce, so the
/// excess becomes fewer and fresher publications instead of dropped ones.
struct PluginPublicationBudget: Sendable {

    static let burst    = 8.0
    static let interval = Duration.milliseconds(250)

    private var tokens         = Self.burst
    private var lastObservation: Duration

    init(at instant: Duration) {
        lastObservation = instant
    }

    /// spend takes one token and returns how long until the next one, zero while tokens remain.
    mutating func spend(at instant: Duration) -> Duration {
        let elapsed     = max(.zero, instant - lastObservation)
        tokens          = min(Self.burst, tokens + elapsed / Self.interval) - 1
        lastObservation = max(lastObservation, instant)

        return tokens >= 1 ? .zero : Self.interval * (1 - tokens)
    }
}
