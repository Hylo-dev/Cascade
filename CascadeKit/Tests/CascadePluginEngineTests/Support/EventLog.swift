//
//  EventLog.swift
//  CascadeKit
//

import CascadeContracts
import Synchronization

/// EventLog records the events a scripted plugin handled, from whatever thread handled them.
final class EventLog: Sendable {

    private let recorded = Mutex<[PluginEvent]>([])

    var events: [PluginEvent] {
        recorded.withLock { $0 }
    }

    func append(_ event: PluginEvent) {
        recorded.withLock { $0.append(event) }
    }
}
