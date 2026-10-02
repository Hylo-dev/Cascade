//
//  PluginPublicationBudget.swift
//  CascadeKit
//

/// PluginPublicationBudget limits how often a plugin changes what is on screen: a burst of
/// eight publications, then one every 250 ms. A plugin past it is not refused; the kernel holds
/// its next event until a token is back, and the events that arrive meanwhile coalesce, so the
/// excess becomes fewer and fresher publications instead of dropped ones.
///
/// Notices refill faster, one every 33 ms. A notice such as the volume HUD's replacement follows a
/// held key, which repeats up to about thirty times a second, and at four a second its level
/// would jump instead of moving; a notice is short and redraws two or three nodes, so the faster
/// pace costs little, and the CPU budget still bounds the plugin.
struct PluginPublicationBudget: Sendable {

    static let burst          = 8.0
    static let interval       = Duration.milliseconds(250)
    static let noticeInterval = Duration.milliseconds(33)

    private let interval       : Duration
    private var tokens         = Self.burst
    private var lastObservation: Duration

    init(
        interval  : Duration = Self.interval,
        at instant: Duration
    ) {
        self.interval   = interval
        lastObservation = instant
    }

    /// spend takes one token and returns how long until the next one, zero while tokens remain.
    mutating func spend(at instant: Duration) -> Duration {
        let elapsed     = max(.zero, instant - lastObservation)
        tokens          = min(Self.burst, tokens + elapsed / interval) - 1
        lastObservation = max(lastObservation, instant)

        return tokens >= 1 ? .zero : interval * (1 - tokens)
    }
}
