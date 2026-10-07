//
//  CaffeinateSession.swift
//  Cascade
//

import Foundation

/// CaffeinateSession serializes assertion ownership away from the UI. A display acquisition
/// failure rolls back the system hold; failed releases retain their IDs for the next stop,
/// rather than silently losing the only references that can release those holds.
actor CaffeinateSession {

    private let backend: any CaffeinateAssertionManaging
    private var system : UInt32?
    private var display: UInt32?
    private var until  : Date?

    init(backend: any CaffeinateAssertionManaging) {
        self.backend = backend
    }

    func snapshot() -> CaffeinateSessionSnapshot {
        let owns = system != nil || display != nil
        return CaffeinateSessionSnapshot(
            isActive        : owns && (until.map { $0 > .now } ?? true),
            hasResources    : owns,
            keepDisplayAwake: display != nil,
            until           : until
        )
    }

    /// start validates a replacement before disturbing the existing session. Native calls
    /// cannot suspend inside this actor, so a stop cannot interleave with partial acquisition.
    func start(
        keepDisplayAwake: Bool,
        until           : Date?
    ) throws {
        if let until {
            let remaining = until.timeIntervalSinceNow
            guard remaining.isFinite, remaining > 0, remaining <= 86_400 else {
                throw CaffeinateFailure.invalidDeadline
            }
        }

        try stop()
        self.until = until
        do {
            system = try backend.acquire(keepDisplayAwake: false, until: until)
            if keepDisplayAwake {
                display = try backend.acquire(keepDisplayAwake: true, until: until)
            }
        } catch {
            // stop keeps any failed rollback ID owned, so shutdown can retry it.
            try? stop()
            throw error
        }
    }

    /// stop attempts both releases even when one fails, and is free when already idle.
    func stop() throws {
        var failure: (any Error)?
        if let display {
            do {
                try backend.release(display)
                self.display = nil
            } catch { failure = error }
        }
        if let system {
            do {
                try backend.release(system)
                self.system = nil
            } catch { if failure == nil { failure = error } }
        }
        if system == nil && display == nil { until = nil }
        if let failure { throw failure }
    }
}
