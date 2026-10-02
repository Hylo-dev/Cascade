//
//  PluginHostSupervisor.swift
//  CascadeKit
//

/// PluginHostSupervisor decides when a lost PluginHost comes back. A host the kernel killed for
/// a hang comes back at once; a crashed one after 1, 5 and then 30 seconds, counting the crashes
/// of the last five minutes; and never sooner than ten seconds after its last launch, because
/// launchd holds back a service that died that young until then, and messages sent meanwhile
/// would only wait. A host that crashed three times in five minutes with no plugin inside it is
/// broken in itself, so it is given up on.
struct PluginHostSupervisor: Sendable {

    /// Loss is how a host was lost.
    enum Loss: Sendable {

        case killed      // The kernel killed it for a hang.
        case crashed     // It died with a plugin inside handle().
        case crashedIdle // It died with nothing in flight.
    }

    static let launchFloor    = Duration.seconds(10)
    static let window         = Duration.seconds(300)
    static let backoff        = [Duration.seconds(1), .seconds(5), .seconds(30)]
    static let idleCrashLimit = 3

    private var lastLaunch : Duration?
    private var crashes    : [Duration] = []
    private var idleCrashes: [Duration] = []

    private(set) var hasGivenUp = false

    mutating func launched(at instant: Duration) {
        lastLaunch = instant
    }

    /// forgive clears the crash history, so a host given up on is tried again.
    mutating func forgive() {
        crashes.removeAll()
        idleCrashes.removeAll()
        hasGivenUp = false
    }

    /// lost records a loss and returns how long to wait before connecting again, or nil once the
    /// host is given up on.
    mutating func lost(
        _ loss    : Loss,
        at instant: Duration
    ) -> Duration? {
        var delay = Duration.zero
        if loss != .killed {
            crashes.removeAll { instant - $0 > Self.window }
            crashes.append(instant)
            delay = Self.backoff[min(crashes.count, Self.backoff.count) - 1]
        }

        if loss == .crashedIdle {
            idleCrashes.removeAll { instant - $0 > Self.window }
            idleCrashes.append(instant)
            if idleCrashes.count >= Self.idleCrashLimit {
                hasGivenUp = true
                return nil
            }
        }

        let floor = lastLaunch.map { $0 + Self.launchFloor - instant } ?? .zero
        return max(delay, floor)
    }
}
