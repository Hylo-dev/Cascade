//
//  CaffeinatePluginSource.swift
//  Cascade
//

import CascadeContracts
import CascadePluginEngine

/// CaffeinatePluginSource is the `caffeinate` catalog source: it hands the service's snapshots
/// to the engine while the plugin holds the lease. Starting it gives the service its emitter,
/// which sends the current state once and then every transition; stopping it only takes the
/// emitter away. The session goes on: the kernel also ends every lease when PluginHost goes away
/// (another plugin's crash, a memory kill, a restart from Settings), and a keep-awake session must
/// survive that. The next `start` hands the plugin the session's current state, so it catches up.
/// Whether a session may run at all follows the plugin's state, through
/// `CaffeinateService.setSessionsAllowed`. The service does all the work on its own queue, so
/// neither call blocks.
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
