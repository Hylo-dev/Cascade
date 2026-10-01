//
//  PluginSurfaceRelay.swift
//  CascadeKit
//

import CascadePluginEngine
import Dispatch
import Synchronization

/// PluginSurfaceRelay carries the engine's deliveries to the main thread, one hop at a time.
/// The engine calls it on its own queue; the relay keeps what arrived under a lock and queues a
/// hop to main only when none is pending, so a burst of publications costs one hop and one
/// render, and an idle engine costs nothing. The hop hands over every change in arrival order,
/// each diff following the one before it, and the refusals the renderer must revert.
nonisolated final class PluginSurfaceRelay: PluginPublicationSink {

    private struct Pending {

        var changes : [PluginPublicationChange] = []
        var rejected: [PluginActionRequest] = []
        var isQueued = false
    }

    private let pending = Mutex(Pending())
    private let handle  : @MainActor @Sendable ([PluginPublicationChange], [PluginActionRequest]) -> Void

    init(handle: @escaping @MainActor @Sendable ([PluginPublicationChange], [PluginActionRequest]) -> Void) {
        self.handle = handle
    }

    func deliver(_ changes: [PluginPublicationChange]) {
        enqueue { $0.changes += changes }
    }

    func reject(_ request: PluginActionRequest) {
        enqueue { $0.rejected.append(request) }
    }

    private func enqueue(_ add: (inout Pending) -> Void) {
        let needsHop = pending.withLock { pending in
            add(&pending)
            defer { pending.isQueued = true }

            return !pending.isQueued
        }
        guard needsHop else { return }

        DispatchQueue.main.async { [self] in
            let taken = pending.withLock { pending in
                defer { pending = Pending() }

                return (pending.changes, pending.rejected)
            }
            MainActor.assumeIsolated {
                handle(taken.0, taken.1)
            }
        }
    }
}
