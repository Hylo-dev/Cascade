//
//  ObservedPluginSource.swift
//  Cascade
//

import CascadeContracts
import CascadePluginEngine

/// ObservedPluginSource lets Cascade see every state of a source as it reaches the engine, before
/// the engine keeps only the latest one for its plugins. The native Bluetooth banner's suppressor
/// needs each new connection, even one a later state would replace before the plugin runs. The
/// observer runs on the thread that delivers the state, before the engine sees it, so it must
/// only hand the state elsewhere.
nonisolated struct ObservedPluginSource: PluginEventSource {

    let source  : any PluginEventSource
    let observer: @Sendable (PluginSourceEvent) -> Void

    func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void) {
        let observer = observer

        source.start { event in
            observer(event)
            emit(event)
        }
    }

    func stop() {
        source.stop()
    }
}
