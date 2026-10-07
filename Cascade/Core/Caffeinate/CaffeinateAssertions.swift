//
//  CaffeinateAssertions.swift
//  Cascade
//

import Foundation
import IOKit.pwr_mgt

/// CaffeinateAssertionKind names the two power assertions a Caffeinate session can hold: the
/// one that keeps the Mac from idling to sleep, and the one that also keeps the display lit.
nonisolated enum CaffeinateAssertionKind: Sendable {

    case system
    case display
}

/// CaffeinateAssertionError is the IOReturn code the system answered when it refused to create,
/// retime or release an assertion. The service publishes it, so the options page can show it.
nonisolated struct CaffeinateAssertionError: Error, Equatable, Sendable {

    let code: Int32
}

/// CaffeinateAssertions is the seam between the Caffeinate service and the power-management
/// subsystem. It is a protocol so the service runs its tests against a fake that can refuse on
/// demand; the service never calls it while holding its lock, so an implementation may block on
/// the system as long as it likes without stalling a reader of the published state. A timeout of
/// nil means none, and the system drops an assertion by itself when its timeout passes, which is
/// what keeps the Mac able to sleep if Cascade hangs or crashes.
nonisolated protocol CaffeinateAssertions: Sendable {

    func acquire(
        _ kind : CaffeinateAssertionKind,
        timeout: TimeInterval?
    ) throws(CaffeinateAssertionError) -> UInt32

    func setTimeout(
        _ timeout     : TimeInterval?,
        of identifier : UInt32
    ) throws(CaffeinateAssertionError)

    func release(_ identifier: UInt32) throws(CaffeinateAssertionError)
}

/// IOKitCaffeinateAssertions holds the real `PreventUserIdleSystemSleep` and
/// `PreventUserIdleDisplaySleep` assertions. Both turn themselves off when their timeout passes,
/// and a timeout is changed in place with `IOPMAssertionSetProperty`, so extending or stepping a
/// session never leaves an instant without an assertion; powerd measures the new timeout from the
/// moment it is set. IOKit reads a timeout of 0 as none, so a timed value is rounded up to whole
/// seconds and never below 1: rounding up errs on the side of keeping the Mac awake a moment
/// longer than the published end, never of dropping the assertion early, and the service's own
/// deadline timer is the one that actually ends the session on time.
nonisolated struct IOKitCaffeinateAssertions: CaffeinateAssertions {

    /// maximumTimeout is the longest timeout IOKit accepts, one day: the end of the duration scale.
    static let maximumTimeout: TimeInterval = 86_400

    func acquire(
        _ kind : CaffeinateAssertionKind,
        timeout: TimeInterval?
    ) throws(CaffeinateAssertionError) -> UInt32 {
        var identifier = IOPMAssertionID(0)
        let result     = IOPMAssertionCreateWithDescription(
            Self.assertionType(of: kind) as CFString,
            Self.name(of: kind) as CFString,
            "User-requested Caffeinate session" as CFString,
            nil,
            nil,
            Self.seconds(timeout),
            kIOPMAssertionTimeoutActionTurnOff as CFString,
            &identifier
        )
        guard result == kIOReturnSuccess else { throw CaffeinateAssertionError(code: result) }

        return identifier
    }

    func setTimeout(
        _ timeout     : TimeInterval?,
        of identifier : UInt32
    ) throws(CaffeinateAssertionError) {
        let result = IOPMAssertionSetProperty(
            identifier,
            kIOPMAssertionTimeoutKey as CFString,
            NSNumber(value: Self.seconds(timeout))
        )
        guard result == kIOReturnSuccess else { throw CaffeinateAssertionError(code: result) }
    }

    func release(_ identifier: UInt32) throws(CaffeinateAssertionError) {
        let result = IOPMAssertionRelease(identifier)
        guard result == kIOReturnSuccess else { throw CaffeinateAssertionError(code: result) }
    }

    private static func seconds(_ timeout: TimeInterval?) -> TimeInterval {
        guard let timeout else { return 0 }

        return min(maximumTimeout, max(1, timeout.rounded(.up)))
    }

    private static func assertionType(of kind: CaffeinateAssertionKind) -> String {
        switch kind {
            case .system : kIOPMAssertPreventUserIdleSystemSleep
            case .display: kIOPMAssertPreventUserIdleDisplaySleep
        }
    }

    private static func name(of kind: CaffeinateAssertionKind) -> String {
        switch kind {
            case .system : "Cascade Caffeinate: system"
            case .display: "Cascade Caffeinate: display"
        }
    }
}
