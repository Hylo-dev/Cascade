//
//  AudioHostSupervision.swift
//  Cascade
//

/// AudioHostSupervision decides when a lost AudioHost comes back. It is the PluginHost
/// supervisor's policy in a smaller shape: every loss is one fault, a fault is answered with a
/// pause of 1, then 5, then 30 seconds, and the third fault inside five minutes means AudioHost
/// is broken in itself, so it is given up on instead of being relaunched forever.
///
/// It is a pure value: the clock is passed in, and nothing here sleeps or schedules. The caller
/// holds it on its own queue, which is why the type is `nonisolated`.
nonisolated struct AudioHostSupervision: Sendable {

    /// Loss is how AudioHost was lost. The kind is part of the contract so the policy can weigh
    /// kinds differently; today each one is a fault of the same weight.
    enum Loss: Sendable {

        case crashed    // The link broke and Cascade did not cause it.
        case hung       // A command went unanswered past the deadline and Cascade killed it.
        case overMemory // It outgrew its memory limit and Cascade killed it.
    }

    static let commandDeadline = Duration.seconds(3)
    static let memoryLimit     = UInt64(64 << 20)
    static let faultLimit      = 3
    static let window          = Duration.seconds(300)
    static let backoff         = [Duration.seconds(1), .seconds(5), .seconds(30)]

    private var faults: [Duration] = []

    private(set) var hasGivenUp = false

    /// forgive clears the fault history, so an AudioHost given up on is tried again.
    mutating func forgive() {
        faults.removeAll()
        hasGivenUp = false
    }

    /// lost records a loss and returns how long to wait before connecting again, or nil once
    /// AudioHost is given up on.
    mutating func lost(
        _ loss    : Loss,
        at instant: Duration
    ) -> Duration? {
        faults.removeAll { instant - $0 > Self.window }
        faults.append(instant)

        if faults.count >= Self.faultLimit {
            hasGivenUp = true
            return nil
        }

        return Self.backoff[min(faults.count, Self.backoff.count) - 1]
    }
}
