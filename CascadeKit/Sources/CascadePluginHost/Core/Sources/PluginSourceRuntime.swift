//
//  PluginSourceRuntime.swift
//  CascadeKit
//

import CascadeContracts
import Synchronization

/// PluginSourceRuntime runs PluginHost's catalog sources for the kernel. A source starts when the
/// kernel leases it and stops when the kernel releases it or its connection ends. Starting a
/// running source restarts it, so whoever asked is primed with its current state.
public final class PluginSourceRuntime: Sendable {

    private let sources: [String: any PluginCatalogSource]
    private let running = Mutex<Set<String>>([])

    public init(sources: [String: any PluginCatalogSource]) {
        self.sources = sources
    }

    func start(
        _ name: String,
        emit  : @escaping @Sendable (PluginSourceEvent) -> Void
    ) {
        guard let source = sources[name] else { return }

        let wasRunning = running.withLock { !$0.insert(name).inserted }
        if wasRunning {
            source.stop()
        }
        source.start(emit)
    }

    func stop(_ name: String) {
        guard let source = sources[name], running.withLock({ $0.remove(name) != nil }) else { return }

        source.stop()
    }

    func stopAll() {
        let names = running.withLock { running in
            defer { running.removeAll() }
            return running
        }

        for name in names.sorted() {
            sources[name]?.stop()
        }
    }
}
