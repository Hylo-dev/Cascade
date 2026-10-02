//
//  ScreenRecordingPluginSource.swift
//  Cascade
//

import CascadeContracts
import CascadePluginEngine
import Dispatch

/// ScreenRecordingPluginSource offers native capture state to the plugin engine, without owning
/// the writer or reading files. One baseline on acquisition and one event per lifecycle change
/// are all it emits. Releasing the source asks the native owner to finalize its writer, so a
/// disabled plugin cannot leave an unattended recording with no Stop control.
@MainActor
final class ScreenRecordingPluginSource: PluginEventSource {

    var onReleased: @MainActor () -> Void = {}

    private var state = PluginScreenRecordingState()
    private var emit: (@Sendable (PluginSourceEvent) -> Void)?

    var isAvailable: Bool { emit != nil }

    func update(_ state: PluginScreenRecordingState) {
        guard self.state != state else { return }

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
