//
//  FakeCatalogSource.swift
//  CascadeKit
//

import CascadeContracts
import CascadePluginHost
import Synchronization

/// FakeCatalogSource is a PluginHost source the test plays: it emits `state` when started and
/// records how often it was started and stopped.
final class FakeCatalogSource: PluginCatalogSource {

    private let counts = Mutex((starts: 0, stops: 0))
    private let state  : PluginSourceEvent

    init(_ state: PluginSourceEvent) {
        self.state = state
    }

    var starts: Int { counts.withLock { $0.starts } }
    var stops : Int { counts.withLock { $0.stops } }

    func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void) {
        counts.withLock { $0.starts += 1 }
        emit(state)
    }

    func stop() {
        counts.withLock { $0.stops += 1 }
    }
}
