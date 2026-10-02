//
//  FakeSource.swift
//  CascadeKit
//

import CascadeContracts
import Synchronization

@testable import CascadePluginEngine

/// FakeSource is a catalog source the test drives by hand.
final class FakeSource: PluginEventSource {

    private let emitter = Mutex<(@Sendable (PluginSourceEvent) -> Void)?>(nil)

    var isRunning: Bool {
        emitter.withLock { $0 != nil }
    }

    func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void) {
        emitter.withLock { $0 = emit }
    }

    func stop() {
        emitter.withLock { $0 = nil }
    }

    func emit(_ event: PluginSourceEvent) {
        emitter.withLock { $0 }?(event)
    }
}
