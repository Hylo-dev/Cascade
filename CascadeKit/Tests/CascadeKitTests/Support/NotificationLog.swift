//
//  NotificationLog.swift
//  CascadeKit
//

import CascadeContracts
import Synchronization

/// NotificationLog records which models Observation reported as changed.
final class NotificationLog: Sendable {

    private let recorded = Mutex<Set<String>>([])

    var names: Set<String> {
        recorded.withLock { $0 }
    }

    func record(_ name: String) {
        recorded.withLock { _ = $0.insert(name) }
    }
}
