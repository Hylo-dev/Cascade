//
//  IOKitCaffeinateAssertions.swift
//  Cascade
//

import Foundation
import IOKit.pwr_mgt

/// IOKitCaffeinateAssertions uses Apple's public idle-sleep contract. An OS timeout turns
/// finite holds off even if Cascade cannot run its deadline callback. TurnOff retains the
/// identifier so the session can still balance acquisition with one release.
///
/// This implementation is independently authored. Functional references and their licenses
/// are recorded in docs/wayfinder/research/2026-10-03-caffeinate-vorssaint.md.
nonisolated struct IOKitCaffeinateAssertions: CaffeinateAssertionManaging {

    func acquire(keepDisplayAwake: Bool, until: Date?) throws -> UInt32 {
        let timeout = until.map { $0.timeIntervalSinceNow } ?? 0
        if until != nil && (!timeout.isFinite || timeout <= 0 || timeout > 86_400) {
            throw CaffeinateFailure.invalidDeadline
        }

        var identifier: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithDescription(
            (keepDisplayAwake ? kIOPMAssertionTypePreventUserIdleDisplaySleep : kIOPMAssertionTypePreventUserIdleSystemSleep) as CFString,
            (keepDisplayAwake ? "Cascade Caffeinate: display" : "Cascade Caffeinate: system") as CFString,
            "User-requested Caffeinate session" as CFString,
            nil,
            nil,
            timeout,
            kIOPMAssertionTimeoutActionTurnOff as CFString,
            &identifier
        )
        guard result == kIOReturnSuccess else { throw CaffeinateFailure.native(result) }

        return identifier
    }

    func release(_ identifier: UInt32) throws {
        let result = IOPMAssertionRelease(identifier)
        guard result == kIOReturnSuccess else { throw CaffeinateFailure.native(result) }
    }
}
