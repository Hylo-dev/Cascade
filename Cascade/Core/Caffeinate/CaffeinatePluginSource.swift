//
//  CaffeinatePluginSource.swift
//  Cascade
//

import CascadeContracts
import CascadePluginEngine

/// CaffeinatePluginSource is the `caffeinate` catalog source: it hands the service's snapshots
/// to the engine while the plugin holds the lease. Starting it gives the service its emitter,
/// which sends the current state once and then every transition; stopping it takes the emitter
/// away, which is how the service learns the lease ended and stops the session, so no assertion
/// outlives its UI. The service does all the work on its own queue, so neither call blocks.
nonisolated final class CaffeinatePluginSource: PluginEventSource {

    private let service: CaffeinateService

    init(service: CaffeinateService) {
        self.service = service
    }

    func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void) {
        service.setEmitter { state in
            guard let event = try? state.event() else { return }

            emit(event)
        }
    }

    func stop() {
        service.setEmitter(nil)
    }
}
