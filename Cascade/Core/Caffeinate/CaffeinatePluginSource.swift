//
//  CaffeinatePluginSource.swift
//  Cascade
//

import CascadeContracts
import CascadePluginEngine
import Dispatch

/// CaffeinatePluginSource leases a native owner independently of visibility. Hiding the
/// notch keeps a requested session alive; disabling the plugin releases the lease and stops
/// it. Each transition emits one snapshot, with no polling or background countdown.
@MainActor
final class CaffeinatePluginSource: PluginEventSource {

    var onReleased: @MainActor () -> Void = {}
    private(set) var state = PluginCaffeinateState()
    private var emit: (@Sendable (PluginSourceEvent) -> Void)?

    var isAvailable: Bool { emit != nil }

    func update(_ state: PluginCaffeinateState) {
        self.state = state
        if let event = try? state.event() { emit?(event) }
    }

    nonisolated func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }

                self.emit = emit
                if let event = try? self.state.event() { emit(event) }
            }
        }
    }

    nonisolated func stop() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.emit != nil else { return }

                self.emit = nil
                self.onReleased()
            }
        }
    }
}
