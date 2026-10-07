//
//  CaffeinateAssertionManaging.swift
//  Cascade
//

import Foundation

/// CaffeinateAssertionManaging is the synchronous IOKit seam. Only the session actor calls
/// it, so native power-service round trips never block the main thread.
nonisolated protocol CaffeinateAssertionManaging: Sendable {

    func acquire(keepDisplayAwake: Bool, until: Date?) throws -> UInt32
    func release(_ identifier: UInt32) throws
}
