//
//  VolumeTapRecovery.swift
//  Cascade
//

import Foundation

/// One recovery per five seconds. Evaluated only on a kernel disable event;
/// there is no watchdog timer or repeated attempt to steal another app's tap.
nonisolated struct VolumeTapRecovery {
    private var lastAttempt: TimeInterval?

    mutating func shouldRetry(at timestamp: TimeInterval, hasPermission: Bool) -> Bool {
        guard hasPermission else { return false }
        guard lastAttempt.map({ timestamp - $0 >= 5 }) ?? true else { return false }
        lastAttempt = timestamp
        return true
    }
}
