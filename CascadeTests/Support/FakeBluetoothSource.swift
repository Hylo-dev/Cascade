//
//  FakeBluetoothSource.swift
//  CascadeTests
//

import CascadeContracts
import CascadePluginEngine
import Synchronization

/// FakeBluetoothSource is a `bluetooth` source the test plays in Cascade's place for PluginHost's,
/// so no test asks macOS for Bluetooth access: it emits a baseline when started, then whatever
/// the test sends, and counts its starts.
nonisolated final class FakeBluetoothSource: PluginEventSource {

    private struct State {

        var emit  : (@Sendable (PluginSourceEvent) -> Void)?
        var starts = 0
    }

    private let state = Mutex(State())

    var starts: Int {
        state.withLock { $0.starts }
    }

    func start(_ emit: @escaping @Sendable (PluginSourceEvent) -> Void) {
        state.withLock { state in
            state.emit    = emit
            state.starts += 1
        }
        send(.baseline(isAvailable: true))
    }

    func stop() {
        state.withLock { $0.emit = nil }
    }

    func send(_ bluetooth: PluginBluetoothState) {
        guard let emit = state.withLock({ $0.emit }), let event = try? bluetooth.event() else { return }

        emit(event)
    }
}
